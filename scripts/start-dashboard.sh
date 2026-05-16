#!/bin/bash
# cc-perf 仪表板启动脚本
# 后台启动服务器，打开浏览器

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_SCRIPT="$SCRIPT_DIR/server.js"
PORT=3100
URL="http://127.0.0.1:$PORT"

echo "启动 cc-perf 仪表板..."

# 后台启动 Node.js 服务器
nohup node "$SERVER_SCRIPT" > /tmp/cc-perf-server.log 2>&1 &
PID=$!

echo "服务器 PID: $PID"
echo "日志: /tmp/cc-perf-server.log"
echo "面板: $URL"

# 等待服务器就绪
for i in $(seq 1 10); do
  if curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null | grep -q 200; then
    echo "服务器已就绪"
    break
  fi
  sleep 0.5
done

# 打开浏览器
open "$URL"
