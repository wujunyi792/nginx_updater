#!/bin/bash
# nginx_updater 一键安装脚本
# 用法:
#   远程安装: curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/wujunyi792/nginx_updater/main/install.sh | sudo bash
#   指定版本: curl -fsSL ... | sudo bash -s -- --version v0.1.4
#   自定义代理: curl -fsSL ... | sudo bash -s -- --proxy https://mirror.ghproxy.com
#   直连(不走代理): curl -fsSL ... | sudo bash -s -- --no-proxy
#   本地安装: sudo ./install.sh --local ./nginx-updater-linux-amd64

set -e

# ============================================================
# 配置
# ============================================================
REPO="wujunyi792/nginx_updater"
BINARY_NAME="nginx-updater"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/nginx_updater"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_FILE="nginx-updater.service"
GITHUB_PROXY="https://ghfast.top"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================================
# 辅助函数
# ============================================================
info()  { echo -e "${GREEN}$*${NC}"; }
warn()  { echo -e "${YELLOW}$*${NC}"; }
error() { echo -e "${RED}$*${NC}" >&2; }
fatal() { error "$@"; exit 1; }

need_cmd() {
    if ! command -v "$1" &>/dev/null; then
        fatal "需要 $1 但未找到，请先安装"
    fi
}

# 构建 URL（自动添加代理前缀）
proxy_url() {
    local url="$1"
    if [ -n "$GITHUB_PROXY" ]; then
        echo "${GITHUB_PROXY}/${url}"
    else
        echo "$url"
    fi
}

# ============================================================
# 检测系统架构
# ============================================================
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) fatal "不支持的架构: $arch" ;;
    esac
}

detect_os() {
    local os
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$os" in
        linux)  echo "linux" ;;
        darwin) echo "darwin" ;;
        *) fatal "不支持的操作系统: $os" ;;
    esac
}

# ============================================================
# 获取最新版本号
# ============================================================
get_latest_version() {
    local url="https://api.github.com/repos/${REPO}/releases/latest"
    local version
    if command -v curl &>/dev/null; then
        version=$(curl -fsSL "$url" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//')
    elif command -v wget &>/dev/null; then
        version=$(wget -qO- "$url" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//')
    else
        fatal "需要 curl 或 wget"
    fi
    if [ -z "$version" ]; then
        fatal "无法获取最新版本号，请检查网络或使用 --version 指定版本"
    fi
    echo "$version"
}

# ============================================================
# 下载二进制文件
# ============================================================
download_binary() {
    local version="$1"
    local os="$2"
    local arch="$3"
    local target="$4"
    local url
    url=$(proxy_url "https://github.com/${REPO}/releases/download/${version}/nginx-updater-${os}-${arch}")

    info "下载 ${url} ..."
    if command -v curl &>/dev/null; then
        curl -fSL --progress-bar -o "$target" "$url"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress -O "$target" "$url"
    fi

    if [ ! -f "$target" ]; then
        fatal "下载失败"
    fi
    chmod +x "$target"
}

# ============================================================
# 内嵌 systemd service 文件
# ============================================================
install_service_file() {
    cat > "${SYSTEMD_DIR}/${SERVICE_FILE}" << 'SERVICEEOF'
[Unit]
Description=nginx_updater - Automatic Nginx upstream configuration updater for Kubernetes
Documentation=https://github.com/wujunyi792/nginx_updater
After=network.target kubernetes.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/nginx-updater
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nginx-updater

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/nginx/conf.d

[Install]
WantedBy=multi-user.target
SERVICEEOF
}

# ============================================================
# 内嵌默认配置模板
# ============================================================
install_default_config() {
    if [ -f "$CONFIG_DIR/config.yaml" ]; then
        warn "配置文件已存在: $CONFIG_DIR/config.yaml，跳过创建"
        return
    fi
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config.yaml" << 'CONFIGEOF'
# nginx_updater 配置文件
# 请根据实际情况修改以下配置

# Kubernetes 服务配置
Namespace: "default"
ServiceName: "your-service"  # 必需：请修改为实际的服务名称
PortName: ""  # 可选

# Nginx 配置
NginxConf: "/etc/nginx/conf.d/upstream.conf"
ReloadCmd:
  - "nginx"
  - "-s"
  - "reload"

# 节点过滤配置
NodeLabelKey: ""  # 可选
NodeLabelVal: ""  # 可选

# 节点状态过滤
IgnoreNotReady: true
CONFIGEOF
    warn "已创建默认配置文件: $CONFIG_DIR/config.yaml"
    error "请务必编辑配置文件并设置正确的 ServiceName！"
}

# ============================================================
# 解析参数
# ============================================================
VERSION=""
LOCAL_BINARY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --version|-v)
            VERSION="$2"
            shift 2
            ;;
        --local|-l)
            LOCAL_BINARY="$2"
            shift 2
            ;;
        --proxy)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                GITHUB_PROXY="$2"
                shift 2
            else
                # 不带参数时使用默认代理
                shift
            fi
            ;;
        --no-proxy)
            GITHUB_PROXY=""
            shift
            ;;
        *)
            # 兼容旧用法: ./install.sh <binary_path>
            LOCAL_BINARY="$1"
            shift
            ;;
    esac
done

# ============================================================
# 主流程
# ============================================================

# 检查 root
if [ "$EUID" -ne 0 ]; then
    fatal "请使用 sudo 运行此脚本"
fi

echo ""
info "=============================="
info "  nginx-updater 安装程序"
info "=============================="
echo ""

# [1/5] 获取二进制文件
warn "[1/5] 准备二进制文件..."

if [ -n "$LOCAL_BINARY" ]; then
    # 本地安装模式
    if [ ! -f "$LOCAL_BINARY" ]; then
        fatal "本地二进制文件不存在: $LOCAL_BINARY"
    fi
    BINARY_SRC="$LOCAL_BINARY"
    chmod +x "$BINARY_SRC"
    info "  使用本地文件: $LOCAL_BINARY"
else
    # 远程下载模式
    OS=$(detect_os)
    ARCH=$(detect_arch)
    if [ -z "$VERSION" ]; then
        info "  检测最新版本..."
        VERSION=$(get_latest_version)
    fi
    info "  版本: $VERSION  平台: ${OS}-${ARCH}"
    if [ -n "$GITHUB_PROXY" ]; then
        info "  代理: $GITHUB_PROXY"
    fi

    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT
    BINARY_SRC="${TMPDIR}/nginx-updater"
    download_binary "$VERSION" "$OS" "$ARCH" "$BINARY_SRC"
fi

# [2/5] 停止旧服务并安装二进制文件
warn "[2/5] 安装二进制文件..."
if systemctl is-active --quiet "$BINARY_NAME" 2>/dev/null; then
    info "  停止正在运行的服务..."
    systemctl stop "$BINARY_NAME"
fi
cp "$BINARY_SRC" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"
info "  已安装到 $INSTALL_DIR/$BINARY_NAME"

# [3/5] 创建配置文件
warn "[3/5] 配置文件..."
install_default_config

# [4/5] 安装 systemd service
warn "[4/5] 安装 systemd 服务..."
install_service_file
info "  systemd 服务文件已写入"

# [5/5] 启动服务
warn "[5/5] 启动服务..."
systemctl daemon-reload
systemctl enable "$BINARY_NAME" --quiet
systemctl restart "$BINARY_NAME"

sleep 2

if systemctl is-active --quiet "$BINARY_NAME"; then
    echo ""
    info "=============================="
    info "  安装完成！服务已启动"
    info "=============================="
    echo ""
    echo "常用命令:"
    echo "  查看状态: sudo systemctl status $BINARY_NAME"
    echo "  查看日志: sudo journalctl -u $BINARY_NAME -f"
    echo "  重启服务: sudo systemctl restart $BINARY_NAME"
    echo "  停止服务: sudo systemctl stop $BINARY_NAME"
    echo ""
    echo "配置文件: $CONFIG_DIR/config.yaml"
else
    echo ""
    fatal "服务启动失败！请检查日志: sudo journalctl -u $BINARY_NAME -n 50"
fi
