#!/bin/bash
# cc-perf 仪表板启动脚本
# 使用 launchd 管理常驻服务

PLIST_NAME="com.cc-perf.dashboard"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
PORT=3100
URL="http://127.0.0.1:$PORT"

# 检查服务是否已加载
if launchctl list "$PLIST_NAME" &>/dev/null; then
    echo "cc-perf 仪表板已在运行"
    echo "面板: $URL"
    open "$URL"
    exit 0
fi

# 检查 plist 文件是否存在
if [[ ! -f "$PLIST_PATH" ]]; then
    echo "错误: 服务未安装，请重新运行 install.sh"
    exit 1
fi

echo "启动 cc-perf 仪表板..."

# 加载服务
launchctl load "$PLIST_PATH" 2>/dev/null

# 等待服务就绪
for i in $(seq 1 10); do
    if curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null | grep -q 200; then
        echo "服务器已就绪"
        echo "面板: $URL"
        open "$URL"
        exit 0
    fi
    sleep 0.5
done

echo "警告: 服务启动超时，请检查日志: /tmp/cc-perf-server.log"
exit 1
