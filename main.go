package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"gopkg.in/yaml.v3"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

const (
	defaultNginxConfPath = "/etc/nginx/conf.d/upstream.conf"
	defaultConfigPath    = "/etc/nginx_updater/config.yaml"
)

type Config struct {
	Namespace      string   `yaml:"Namespace"`
	ServiceName    string   `yaml:"ServiceName"`
	PortName       string   `yaml:"PortName"`
	NginxConf      string   `yaml:"NginxConf"`
	ReloadCmd      []string `yaml:"ReloadCmd"`
	NodeLabelKey   string   `yaml:"NodeLabelKey"`
	NodeLabelVal   string   `yaml:"NodeLabelVal"`
	IgnoreNotReady bool     `yaml:"IgnoreNotReady"`
}

func main() {
	cfg := parseConfig()
	logger := log.New(os.Stdout, "[nginx-updater] ", log.LstdFlags)
	clientset, err := getKubernetesClient()
	if err != nil {
		logger.Fatalf("failed to create k8s client: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	// 优雅退出处理
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		logger.Println("Received termination signal, exiting...")
		cancel()
	}()
	// 初次生成配置
	err = updateNginxConfig(ctx, clientset, cfg, logger)
	if err != nil {
		logger.Fatalf("initial nginx config update failed: %v", err)
	}
	// 开始监听节点变化
	watchNodes(ctx, clientset, cfg, logger)
}
func parseConfig() *Config {
	// 先尝试从配置文件加载
	cfg := loadConfigFromFile(defaultConfigPath)
	if cfg == nil {
		cfg = &Config{}
	}

	// 命令行参数（优先级高于配置文件）
	var (
		namespace      = flag.String("namespace", "", "Kubernetes namespace of the service")
		serviceName    = flag.String("service", "", "Kubernetes service name")
		portName       = flag.String("port-name", "", "Service port name (optional)")
		nginxConf      = flag.String("nginx-conf", "", "Path to nginx upstream conf file")
		reloadCmd      = flag.String("reload-cmd", "", "Command to reload nginx (space separated)")
		nodeLabelKey   = flag.String("node-label-key", "", "Node label key to filter nodes (optional)")
		nodeLabelVal   = flag.String("node-label-val", "", "Node label value to filter nodes (optional)")
		ignoreNotReady = flag.Bool("ignore-not-ready", false, "Ignore nodes that are not Ready (default: false)")
		configPath     = flag.String("config", "", "Path to config file (default: /etc/nginx_updater/config.yaml)")
	)
	flag.Parse()

	// 如果指定了自定义配置文件路径，重新加载
	if *configPath != "" && *configPath != defaultConfigPath {
		if fileCfg := loadConfigFromFile(*configPath); fileCfg != nil {
			cfg = fileCfg
		}
	}

	// 命令行参数覆盖配置文件（如果提供了）
	if *namespace != "" {
		cfg.Namespace = *namespace
	}
	if *serviceName != "" {
		cfg.ServiceName = *serviceName
	}
	if *portName != "" {
		cfg.PortName = *portName
	}
	if *nginxConf != "" {
		cfg.NginxConf = *nginxConf
	}
	if *reloadCmd != "" {
		cfg.ReloadCmd = strings.Split(*reloadCmd, " ")
	}
	if *nodeLabelKey != "" {
		cfg.NodeLabelKey = *nodeLabelKey
	}
	if *nodeLabelVal != "" {
		cfg.NodeLabelVal = *nodeLabelVal
	}
	// 对于布尔值，如果命令行提供了就使用（通过检查是否在命令行中）
	// 由于 flag.Bool 默认值为 false，我们需要通过检查 flag.Visit 来判断
	ignoreNotReadySet := false
	flag.Visit(func(f *flag.Flag) {
		if f.Name == "ignore-not-ready" {
			ignoreNotReadySet = true
		}
	})
	if ignoreNotReadySet {
		cfg.IgnoreNotReady = *ignoreNotReady
	}

	// 设置默认值
	if cfg.Namespace == "" {
		cfg.Namespace = "default"
	}
	if cfg.NginxConf == "" {
		cfg.NginxConf = defaultNginxConfPath
	}
	if len(cfg.ReloadCmd) == 0 {
		cfg.ReloadCmd = []string{"nginx", "-s", "reload"}
	}

	// 验证必需参数
	if cfg.ServiceName == "" {
		log.Fatal("service name must be specified (via config file or --service flag)")
	}

	return cfg
}

func loadConfigFromFile(path string) *Config {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		log.Printf("Warning: failed to read config file %s: %v", path, err)
		return nil
	}

	cfg := &Config{}
	if err := yaml.Unmarshal(data, cfg); err != nil {
		log.Printf("Warning: failed to parse config file %s: %v", path, err)
		return nil
	}

	return cfg
}
func getKubernetesClient() (*kubernetes.Clientset, error) {
	// 优先使用集群内配置
	config, err := rest.InClusterConfig()
	if err != nil {
		// 失败则尝试本地 kubeconfig
		kubeconfig := os.Getenv("KUBECONFIG")
		if kubeconfig == "" {
			kubeconfig = os.ExpandEnv("$HOME/.kube/config")
		}
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
		if err != nil {
			return nil, err
		}
	}
	return kubernetes.NewForConfig(config)
}
func watchNodes(ctx context.Context, clientset *kubernetes.Clientset, cfg *Config, logger *log.Logger) {
	for {
		watcher, err := clientset.CoreV1().Nodes().Watch(ctx, metav1.ListOptions{})
		if err != nil {
			logger.Printf("failed to start node watcher: %v, retrying in 5s", err)
			select {
			case <-time.After(5 * time.Second):
				continue
			case <-ctx.Done():
				return
			}
		}
		logger.Println("Started watching nodes for changes")
		ch := watcher.ResultChan()
	watchLoop:
		for {
			select {
			case event, ok := <-ch:
				if !ok {
					logger.Println("Node watch channel closed, restarting watcher")
					break watchLoop
				}
				logger.Printf("Node event: %s", event.Type)
				// 每次事件都重新生成配置和reload
				err := updateNginxConfig(ctx, clientset, cfg, logger)
				if err != nil {
					logger.Printf("failed to update nginx config: %v", err)
				}
			case <-ctx.Done():
				watcher.Stop()
				logger.Println("Context cancelled, stopping node watcher")
				return
			}
		}
	}
}
func updateNginxConfig(ctx context.Context, clientset *kubernetes.Clientset, cfg *Config, logger *log.Logger) error {
	port, err := getServicePort(ctx, clientset, cfg.Namespace, cfg.ServiceName, cfg.PortName)
	if err != nil {
		return fmt.Errorf("getServicePort error: %w", err)
	}
	logger.Printf("Using port %d for service %s/%s", port, cfg.Namespace, cfg.ServiceName)
	ips, err := getNodeIPs(ctx, clientset, cfg.NodeLabelKey, cfg.NodeLabelVal, cfg.IgnoreNotReady)
	if err != nil {
		return fmt.Errorf("getNodeIPs error: %w", err)
	}
	if len(ips) == 0 {
		return fmt.Errorf("no nodes found with specified label filter")
	}
	logger.Printf("Found nodes: %v", ips)
	err = generateNginxConf(cfg.NginxConf, ips, port)
	if err != nil {
		return fmt.Errorf("generateNginxConf error: %w", err)
	}
	logger.Printf("Nginx config updated at %s", cfg.NginxConf)
	err = reloadNginx(cfg.ReloadCmd)
	if err != nil {
		return fmt.Errorf("reloadNginx error: %w", err)
	}
	logger.Println("Nginx reloaded successfully")
	return nil
}
func getServicePort(ctx context.Context, clientset *kubernetes.Clientset, namespace, svcName, portName string) (int32, error) {
	svc, err := clientset.CoreV1().Services(namespace).Get(ctx, svcName, metav1.GetOptions{})
	if err != nil {
		return 0, err
	}
	for _, port := range svc.Spec.Ports {
		if portName == "" || port.Name == portName {
			if port.NodePort != 0 {
				return port.NodePort, nil
			}
			return port.Port, nil
		}
	}
	return 0, fmt.Errorf("port %q not found in service %s/%s", portName, namespace, svcName)
}
func getNodeIPs(ctx context.Context, clientset *kubernetes.Clientset, labelKey, labelVal string, ignoreNotReady bool) ([]string, error) {
	var opts metav1.ListOptions
	if labelKey != "" {
		if labelVal != "" {
			opts.LabelSelector = fmt.Sprintf("%s=%s", labelKey, labelVal)
		} else {
			// 如果只有 key 没有 value，使用 key 存在即可的选择器
			opts.LabelSelector = labelKey
		}
	}
	nodes, err := clientset.CoreV1().Nodes().List(ctx, opts)
	if err != nil {
		return nil, err
	}
	var ips []string
	for _, node := range nodes.Items {
		// 检查节点是否 Ready
		if ignoreNotReady {
			isReady := false
			for _, condition := range node.Status.Conditions {
				if condition.Type == corev1.NodeReady {
					if condition.Status == corev1.ConditionTrue {
						isReady = true
					}
					break
				}
			}
			if !isReady {
				continue
			}
		}

		for _, addr := range node.Status.Addresses {
			if addr.Type == corev1.NodeInternalIP {
				ips = append(ips, addr.Address)
				break
			}
		}
	}
	return ips, nil
}
func generateNginxConf(path string, ips []string, port int32) error {
	var builder strings.Builder
	builder.WriteString("upstream backend {\n")
	for _, ip := range ips {
		builder.WriteString(fmt.Sprintf("    server %s:%d;\n", ip, port))
	}
	builder.WriteString("}\n")
	return os.WriteFile(path, []byte(builder.String()), 0644)
}
func reloadNginx(cmdArgs []string) error {
	if len(cmdArgs) == 0 {
		return fmt.Errorf("reload command not specified")
	}
	cmd := exec.Command(cmdArgs[0], cmdArgs[1:]...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("reload command failed: %v, output: %s", err, string(output))
	}
	return nil
}
