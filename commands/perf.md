# /perf — cc-perf 性能监控命令

用法：
- `/perf` — 显示当前会话耗时摘要
- `/perf start` — 启动仪表板服务器并打开浏览器
- `/perf stop` — 停止仪表板服务器
- `/perf status` — 查看计时统计摘要

## 操作指南

### 显示摘要
当用户输入 `/perf` 不带参数时，运行：
```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/server.js" summary
```

### 启动仪表板
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/start-dashboard.sh"
```

### 停止仪表板
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/stop-dashboard.sh"
```

### 查看状态
检查 `~/.claude/timing/` 目录下的 JSONL 文件，统计最近会话的调用次数和总耗时。
