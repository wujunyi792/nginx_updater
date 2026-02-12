# nginx_updater

自动监听 Kubernetes 节点变化，更新 Nginx upstream 配置并 reload，支持多组 upstream、节点标签过滤、NotReady 节点过滤。配置无变化时自动跳过 reload。

## 安装

### 一键安装（推荐）

国内用户（默认通过 ghfast.top 加速）：

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/wujunyi792/nginx_updater/main/install.sh | sudo bash
```

海外用户（直连）：

```bash
curl -fsSL https://raw.githubusercontent.com/wujunyi792/nginx_updater/main/install.sh | sudo bash -s -- --no-proxy
```

指定版本：

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/wujunyi792/nginx_updater/main/install.sh | sudo bash -s -- --version v0.2.1
```

自定义代理：

```bash
curl -fsSL ... | sudo bash -s -- --proxy https://mirror.ghproxy.com
```

使用本地二进制文件：

```bash
sudo ./install.sh --local ./nginx-updater-linux-amd64
```

## 配置

配置文件路径：`/etc/nginx_updater/config.yaml`

### 多组 upstream（推荐）

```yaml
Namespace: "higress-system"
ServiceName: "higress-gateway"

Upstreams:
  - Name: "backend_http"
    PortName: "http"
  - Name: "backend_https"
    PortName: "https"

NginxConf: "/etc/nginx/conf.d/upstream.conf"
ReloadCmd:
  - "nginx"
  - "-s"
  - "reload"

NodeLabelKey: "node-role.kubernetes.io/worker"
NodeLabelVal: ""
IgnoreNotReady: true
```

生成的配置：

```nginx
upstream backend_http {
    server 10.0.1.1:30080;
    server 10.0.1.2:30080;
}

upstream backend_https {
    server 10.0.1.1:30443;
    server 10.0.1.2:30443;
}
```

### 单 upstream（向后兼容）

```yaml
Namespace: "higress-system"
ServiceName: "higress-gateway"
PortName: "http"

NginxConf: "/etc/nginx/conf.d/upstream.conf"
ReloadCmd:
  - "nginx"
  - "-s"
  - "reload"

IgnoreNotReady: true
```

不配置 `Upstreams` 时自动生成 `upstream backend { ... }`。

### 命令行参数

命令行参数优先级高于配置文件，多 upstream 场景请使用配置文件。

| 参数 | 说明 | 默认值 | 必需 |
|------|------|--------|------|
| `--namespace` | Kubernetes 命名空间 | `default` | 否 |
| `--service` | Kubernetes 服务名称 | - | **是** |
| `--port-name` | 服务端口名称 | - | 否 |
| `--nginx-conf` | Nginx upstream 配置文件路径 | `/etc/nginx/conf.d/upstream.conf` | 否 |
| `--reload-cmd` | Nginx 重载命令（空格分隔） | `nginx -s reload` | 否 |
| `--node-label-key` | 节点标签键 | - | 否 |
| `--node-label-val` | 节点标签值 | - | 否 |
| `--ignore-not-ready` | 忽略 NotReady 节点 | `false` | 否 |
| `--config` | 配置文件路径 | `/etc/nginx_updater/config.yaml` | 否 |

## 服务管理

```bash
sudo systemctl status nginx-updater    # 查看状态
sudo journalctl -u nginx-updater -f    # 查看日志
sudo systemctl restart nginx-updater   # 重启
sudo systemctl stop nginx-updater      # 停止
```

## 卸载

```bash
# 交互式卸载
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/wujunyi792/nginx_updater/main/uninstall.sh | sudo bash

# 完全卸载（删除配置文件）
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/wujunyi792/nginx_updater/main/uninstall.sh | sudo bash -s -- --purge

# 卸载但保留配置文件
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/wujunyi792/nginx_updater/main/uninstall.sh | sudo bash -s -- --keep-config
```
