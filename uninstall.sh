#!/bin/bash
# nginx_updater 卸载脚本
# 用法:
#   sudo ./uninstall.sh              # 交互式，询问是否删除配置
#   sudo ./uninstall.sh --purge      # 完全卸载，删除配置文件
#   sudo ./uninstall.sh --keep-config # 保留配置文件

set -e

BINARY_NAME="nginx-updater"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/nginx_updater"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_FILE="nginx-updater.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}$*${NC}"; }
warn()  { echo -e "${YELLOW}$*${NC}"; }
fatal() { echo -e "${RED}$*${NC}" >&2; exit 1; }

# 解析参数
PURGE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --purge)       PURGE="yes"; shift ;;
        --keep-config) PURGE="no";  shift ;;
        *) shift ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    fatal "请使用 sudo 运行此脚本"
fi

echo ""
warn "即将卸载 nginx-updater，是否继续？[y/N]"
read -r confirm < /dev/tty
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "已取消"
    exit 0
fi

echo ""

# 停止并禁用服务
if systemctl is-active --quiet "$BINARY_NAME" 2>/dev/null; then
    warn "[1/4] 停止服务..."
    systemctl stop "$BINARY_NAME"
    info "  服务已停止"
else
    info "[1/4] 服务未运行，跳过"
fi

if systemctl is-enabled --quiet "$BINARY_NAME" 2>/dev/null; then
    systemctl disable "$BINARY_NAME" --quiet
fi

# 删除 systemd service 文件
if [ -f "${SYSTEMD_DIR}/${SERVICE_FILE}" ]; then
    warn "[2/4] 删除 systemd 服务文件..."
    rm -f "${SYSTEMD_DIR}/${SERVICE_FILE}"
    systemctl daemon-reload
    info "  已删除"
else
    info "[2/4] 服务文件不存在，跳过"
fi

# 删除二进制文件
if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
    warn "[3/4] 删除二进制文件..."
    rm -f "${INSTALL_DIR}/${BINARY_NAME}"
    info "  已删除 ${INSTALL_DIR}/${BINARY_NAME}"
else
    info "[3/4] 二进制文件不存在，跳过"
fi

# 配置文件
if [ -d "$CONFIG_DIR" ]; then
    if [ "$PURGE" = "yes" ]; then
        warn "[4/4] 删除配置目录..."
        rm -rf "$CONFIG_DIR"
        info "  配置目录已删除"
    elif [ "$PURGE" = "no" ]; then
        info "[4/4] 保留配置目录: $CONFIG_DIR"
    else
        warn "[4/4] 发现配置目录: $CONFIG_DIR"
        warn "  是否删除配置文件？[y/N]"
        read -r del_conf < /dev/tty
        if [ "$del_conf" = "y" ] || [ "$del_conf" = "Y" ]; then
            rm -rf "$CONFIG_DIR"
            info "  配置目录已删除"
        else
            info "  已保留配置目录"
        fi
    fi
else
    info "[4/4] 配置目录不存在，跳过"
fi

echo ""
info "=============================="
info "  nginx-updater 已卸载"
info "=============================="
echo ""
