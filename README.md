# nginx_updater

nginx_updater 是一个用于自动更新 Nginx upstream 配置的 Kubernetes 工具。它监听 Kubernetes 集群中的节点变化，并自动更新 Nginx 的 upstream 配置，将流量路由到集群中的节点。

## 功能特性

- ✅ 自动监听 Kubernetes 节点变化
- ✅ 自动生成和更新 Nginx upstream 配置
- ✅ 支持通过节点标签过滤节点
- ✅ 支持忽略 NotReady 状态的节点
- ✅ 支持配置文件（YAML）和命令行参数
- ✅ 命令行参数优先级高于配置文件
- ✅ 优雅退出处理

## 安装

### 快速安装（推荐）

使用安装脚本快速安装和启动服务：

```bash
# 从 GitHub Release 下载二进制文件
wget https://github.com/wujunyi792/nginx_updater/releases/download/v1.0.0/nginx-updater-linux-amd64
chmod +x nginx-updater-linux-amd64

# 运行安装脚本
sudo ./install.sh nginx-updater-linux-amd64
```

或者如果二进制文件在当前目录：

```bash
sudo ./install.sh
```

安装脚本会自动完成：
- 安装二进制文件到 `/usr/local/bin/`
- 创建配置目录 `/etc/nginx_updater/`
- 创建示例配置文件（如果不存在）
- 安装并启动 systemd 服务

### 手动安装

#### 编译

```bash
cd nginx_updater
go build -o nginx-updater main.go
```

#### 二进制文件部署

将编译好的 `nginx-updater` 二进制文件复制到目标服务器：

```bash
sudo cp nginx-updater /usr/local/bin/
sudo chmod +x /usr/local/bin/nginx-updater
```

## 配置

### 配置文件

nginx_updater 支持通过配置文件 `/etc/nginx_updater/config.yaml` 进行配置。如果配置文件不存在，程序仍可通过命令行参数运行。

创建配置文件：

```bash
sudo mkdir -p /etc/nginx_updater
sudo nano /etc/nginx_updater/config.yaml
```

配置文件示例：

```yaml
# Kubernetes 服务配置
Namespace: "higress-system"
ServiceName: "higress-gateway"
PortName: "http"  # 可选，如果不指定则使用服务的第一个端口

# Nginx 配置
NginxConf: "/etc/nginx/conf.d/upstream.conf"
ReloadCmd:
  - "nginx"
  - "-s"
  - "reload"

# 节点过滤配置
NodeLabelKey: "node-role.kubernetes.io/worker"  # 可选
NodeLabelVal: ""  # 可选，如果为空则匹配所有具有该 label key 的节点

# 节点状态过滤
IgnoreNotReady: true  # 是否忽略 NotReady 状态的节点，默认为 false
```

### 命令行参数

所有配置项都可以通过命令行参数覆盖，命令行参数的优先级高于配置文件。

```bash
nginx-updater \
  --namespace=higress-system \
  --service=higress-gateway \
  --port-name=http \
  --nginx-conf=/etc/nginx/conf.d/upstream.conf \
  --reload-cmd="nginx -s reload" \
  --node-label-key=node-role.kubernetes.io/worker \
  --node-label-val="" \
  --ignore-not-ready \
  --config=/etc/nginx_updater/config.yaml
```

#### 命令行参数说明

| 参数 | 说明 | 默认值 | 必需 |
|------|------|--------|------|
| `--namespace` | Kubernetes 命名空间 | `default` | 否 |
| `--service` | Kubernetes 服务名称 | - | **是** |
| `--port-name` | 服务端口名称（可选） | - | 否 |
| `--nginx-conf` | Nginx upstream 配置文件路径 | `/etc/nginx/conf.d/upstream.conf` | 否 |
| `--reload-cmd` | Nginx 重载命令（空格分隔） | `nginx -s reload` | 否 |
| `--node-label-key` | 节点标签键（用于过滤节点） | - | 否 |
| `--node-label-val` | 节点标签值（用于过滤节点） | - | 否 |
| `--ignore-not-ready` | 忽略 NotReady 状态的节点 | `false` | 否 |
| `--config` | 配置文件路径 | `/etc/nginx_updater/config.yaml` | 否 |

## 使用方法

### 1. 使用配置文件

创建配置文件后，直接运行：

```bash
nginx-updater
```

### 2. 使用命令行参数

```bash
nginx-updater \
  --namespace=higress-system \
  --service=higress-gateway \
  --port-name=http
```

### 3. 混合使用（配置文件 + 命令行覆盖）

```bash
# 使用配置文件，但覆盖服务名称
nginx-updater --service=another-service
```

## 工作原理

1. **初始化**：程序启动时，首先从配置文件（如果存在）加载配置，然后应用命令行参数覆盖
2. **获取服务端口**：从 Kubernetes API 获取指定服务的端口信息
3. **获取节点 IP**：根据配置的节点标签过滤节点，获取节点的内部 IP 地址
4. **生成配置**：生成 Nginx upstream 配置文件
5. **重载 Nginx**：执行配置的重载命令
6. **监听变化**：持续监听 Kubernetes 节点变化，当节点发生变化时自动更新配置

## 生成的配置文件格式

程序会在指定的路径生成如下格式的 Nginx upstream 配置：

```nginx
upstream backend {
    server 10.0.1.1:30080;
    server 10.0.1.2:30080;
    server 10.0.1.3:30080;
}
```

## Kubernetes 权限要求

nginx_updater 需要以下 Kubernetes 权限：

- 读取 Service 资源（获取服务端口）
- 读取和监听 Node 资源（获取节点 IP 和监听节点变化）

如果运行在 Kubernetes 集群内，需要创建相应的 ServiceAccount、Role 和 RoleBinding。

示例 RBAC 配置：

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nginx-updater
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: nginx-updater
  namespace: default
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nginx-updater
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: nginx-updater
subjects:
- kind: ServiceAccount
  name: nginx-updater
  namespace: default
```

## 系统服务

nginx_updater 可以作为 systemd 服务运行。

### 使用安装脚本（推荐）

```bash
sudo ./install.sh [binary_path]
```

### 手动安装 systemd 服务

```bash
sudo cp nginx-updater.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable nginx-updater
sudo systemctl start nginx-updater
```

### 服务管理

查看服务状态：

```bash
sudo systemctl status nginx-updater
```

查看日志：

```bash
sudo journalctl -u nginx-updater -f
```

重启服务：

```bash
sudo systemctl restart nginx-updater
```

停止服务：

```bash
sudo systemctl stop nginx-updater
```

## 故障排查

### 问题：无法连接到 Kubernetes API

**解决方案**：
- 检查是否在 Kubernetes 集群内运行，或配置了正确的 `KUBECONFIG` 环境变量
- 检查 Kubernetes 权限配置

### 问题：找不到节点

**解决方案**：
- 检查节点标签配置是否正确
- 如果启用了 `ignore_not_ready`，检查是否有 Ready 状态的节点
- 使用 `kubectl get nodes --show-labels` 查看节点标签

### 问题：Nginx 重载失败

**解决方案**：
- 检查 `reload_cmd` 配置是否正确
- 检查是否有执行 Nginx 重载命令的权限
- 检查 Nginx 配置文件语法是否正确

### 问题：生成的配置文件为空

**解决方案**：
- 检查是否有匹配的节点
- 检查节点是否有内部 IP 地址
- 查看程序日志获取详细错误信息

## 开发

### 依赖

- Go 1.25.2 或更高版本
- Kubernetes client-go 库

### 构建

```bash
go mod download
go build -o nginx-updater main.go
```

## 许可证

[根据项目许可证填写]
