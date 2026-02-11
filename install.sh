#!/bin/bash
# nginx_updater 快速安装和启动脚本
# 使用方法: sudo ./install.sh [binary_path]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
BINARY_NAME="nginx-updater"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/nginx_updater"
SERVICE_FILE="nginx-updater.service"
SYSTEMD_DIR="/etc/systemd/system"

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}错误: 请使用 sudo 运行此脚本${NC}"
    exit 1
fi

# 获取二进制文件路径
if [ -n "$1" ]; then
    BINARY_PATH="$1"
else
    # 尝试在当前目录查找
    if [ -f "./nginx-updater" ]; then
        BINARY_PATH="./nginx-updater"
    elif [ -f "./nginx_updater/nginx-updater" ]; then
        BINARY_PATH="./nginx_updater/nginx-updater"
    else
        echo -e "${RED}错误: 未找到 nginx-updater 二进制文件${NC}"
        echo "请指定二进制文件路径: sudo ./install.sh /path/to/nginx-updater"
        exit 1
    fi
fi

# 检查二进制文件是否存在
if [ ! -f "$BINARY_PATH" ]; then
    echo -e "${RED}错误: 二进制文件不存在: $BINARY_PATH${NC}"
    exit 1
fi

# 检查二进制文件是否可执行
if [ ! -x "$BINARY_PATH" ]; then
    echo -e "${YELLOW}警告: 二进制文件不可执行，正在添加执行权限...${NC}"
    chmod +x "$BINARY_PATH"
fi

echo -e "${GREEN}开始安装 nginx_updater...${NC}"

# 1. 安装二进制文件
echo -e "${YELLOW}[1/5] 安装二进制文件...${NC}"
# 如果服务正在运行，先停止，避免 "Text file busy" 错误
if systemctl is-active --quiet "$BINARY_NAME" 2>/dev/null; then
    echo -e "${YELLOW}  服务正在运行，先停止服务...${NC}"
    systemctl stop "$BINARY_NAME"
fi
cp "$BINARY_PATH" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"
echo -e "${GREEN}✓ 二进制文件已安装到 $INSTALL_DIR/$BINARY_NAME${NC}"

# 2. 创建配置目录
echo -e "${YELLOW}[2/5] 创建配置目录...${NC}"
mkdir -p "$CONFIG_DIR"
echo -e "${GREEN}✓ 配置目录已创建: $CONFIG_DIR${NC}"

# 3. 检查配置文件
if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
    echo -e "${YELLOW}[3/5] 配置文件不存在，创建示例配置...${NC}"
    if [ -f "config.yaml.example" ]; then
        cp config.yaml.example "$CONFIG_DIR/config.yaml"
        echo -e "${GREEN}✓ 已创建示例配置文件: $CONFIG_DIR/config.yaml${NC}"
        echo -e "${YELLOW}  请编辑配置文件并设置正确的参数！${NC}"
    else
        cat > "$CONFIG_DIR/config.yaml" << 'EOF'
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
EOF
        echo -e "${GREEN}✓ 已创建默认配置文件: $CONFIG_DIR/config.yaml${NC}"
        echo -e "${RED}  警告: 请务必编辑配置文件并设置正确的 ServiceName！${NC}"
    fi
else
    echo -e "${GREEN}[3/5] 配置文件已存在，跳过创建${NC}"
fi

# 4. 安装 systemd service
echo -e "${YELLOW}[4/5] 安装 systemd 服务...${NC}"
if [ -f "$SERVICE_FILE" ]; then
    cp "$SERVICE_FILE" "$SYSTEMD_DIR/$SERVICE_FILE"
    echo -e "${GREEN}✓ systemd 服务文件已安装${NC}"
else
    echo -e "${RED}错误: 未找到 $SERVICE_FILE 文件${NC}"
    exit 1
fi

# 5. 重载 systemd 并启动服务
echo -e "${YELLOW}[5/5] 启动服务...${NC}"
systemctl daemon-reload
systemctl enable "$BINARY_NAME"
systemctl restart "$BINARY_NAME"

# 等待服务启动
sleep 2

# 检查服务状态
if systemctl is-active --quiet "$BINARY_NAME"; then
    echo -e "${GREEN}✓ 服务已成功启动！${NC}"
    echo ""
    echo -e "${GREEN}服务状态:${NC}"
    systemctl status "$BINARY_NAME" --no-pager -l
    echo ""
    echo -e "${GREEN}安装完成！${NC}"
    echo ""
    echo "常用命令:"
    echo "  查看状态: sudo systemctl status $BINARY_NAME"
    echo "  查看日志: sudo journalctl -u $BINARY_NAME -f"
    echo "  重启服务: sudo systemctl restart $BINARY_NAME"
    echo "  停止服务: sudo systemctl stop $BINARY_NAME"
    echo ""
    echo "配置文件位置: $CONFIG_DIR/config.yaml"
else
    echo -e "${RED}✗ 服务启动失败！${NC}"
    echo -e "${YELLOW}请检查日志: sudo journalctl -u $BINARY_NAME -n 50${NC}"
    exit 1
fi

