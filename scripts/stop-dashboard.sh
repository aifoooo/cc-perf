#!/bin/bash
# cc-perf 仪表板停止脚本
# 使用 launchd 管理常驻服务

PLIST_NAME="com.cc-perf.dashboard"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

# 检查服务是否在运行
if ! launchctl list "$PLIST_NAME" &>/dev/null; then
    echo "cc-perf 仪表板未运行"
    exit 0
fi

echo "停止 cc-perf 仪表板..."

# 停止并卸载服务
launchctl unload "$PLIST_PATH" 2>/dev/null

echo "已停止"
