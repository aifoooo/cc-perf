#!/bin/bash
# cc-perf 仪表板停止脚本

TIMING_DIR="$HOME/.claude/timing"
PID_FILE="$TIMING_DIR/.server.pid"

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    echo "停止 cc-perf 仪表板 (PID: $PID)..."
    kill "$PID"
    rm -f "$PID_FILE"
    echo "已停止"
  else
    echo "服务器未在运行（僵尸 PID 文件已清理）"
    rm -f "$PID_FILE"
  fi
else
  echo "cc-perf 仪表板未运行（无 PID 文件）"
fi
