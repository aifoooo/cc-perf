#!/bin/bash
# cc-perf 卸载脚本

set -e

HOME_DIR="$HOME"
SETTINGS="$HOME_DIR/.claude/settings.json"
TIMING_DIR="$HOME_DIR/.claude/timing"
CACHE_DIR="$HOME_DIR/.claude/plugins/cache/local/cc-perf"
COMMANDS_DIR="$HOME_DIR/.claude/commands"
INSTALLED_PLUGINS="$HOME_DIR/.claude/plugins/installed_plugins.json"

echo "=== cc-perf 卸载 ==="

# 1. 移除 hooks
echo -n "移除 hooks... "
if [[ -f "$SETTINGS" ]]; then
    node -e "
const fs=require('fs');
const d=JSON.parse(fs.readFileSync('$SETTINGS','utf8'));
if(d.hooks){
  for(const e of ['PreToolUse','PostToolUse','PostToolUseFailure']){
    if(d.hooks[e]) d.hooks[e]=d.hooks[e].filter(h=>!(h.hooks&&h.hooks[0]&&h.hooks[0].command&&h.hooks[0].command.includes('cc-perf')));
  }
}
if(d.enabledPlugins) delete d.enabledPlugins['cc-perf@local'];
fs.writeFileSync('$SETTINGS',JSON.stringify(d,null,2));
" 2>/dev/null && echo "OK" || echo "失败"
fi

# 2. 移除安装记录
echo -n "移除插件注册... "
[[ -f "$INSTALLED_PLUGINS" ]] && node -e "
const fs=require('fs');
const d=JSON.parse(fs.readFileSync('$INSTALLED_PLUGINS','utf8'));
delete d.plugins['cc-perf@local'];
fs.writeFileSync('$INSTALLED_PLUGINS',JSON.stringify(d,null,2));
" 2>/dev/null
echo "OK"

# 3. 移除符号链接和缓存
echo -n "移除缓存... "
rm -rf "$CACHE_DIR" 2>/dev/null && echo "OK" || echo "跳过"

# 4. 移除全局命令
echo -n "移除 /perf 命令... "
rm -f "$COMMANDS_DIR/perf.md" 2>/dev/null && echo "OK" || echo "跳过"

# 5. 清理 settings.local.json
echo -n "清理 settings.local.json... "
if [[ -f "$HOME_DIR/.claude/settings.local.json" ]]; then
    node -e "
const fs=require('fs');
const d=JSON.parse(fs.readFileSync('$HOME_DIR/.claude/settings.local.json','utf8'));
if(d.hooks){
  for(const e of ['PreToolUse','PostToolUse','PostToolUseFailure']){
    if(d.hooks[e]) d.hooks[e]=d.hooks[e].filter(h=>!(h.hooks&&h.hooks[0]&&h.hooks[0].command&&h.hooks[0].command.includes('cc-perf')));
  }
}
// 如果文件已空，删除整个文件
const hasHooks = d.hooks && Object.values(d.hooks).some(a=>a.length>0);
if(!hasHooks){
  try{fs.unlinkSync('$HOME_DIR/.claude/settings.local.json');}catch{}
}
fs.writeFileSync('$HOME_DIR/.claude/settings.local.json',JSON.stringify(d,null,2));
" 2>/dev/null
fi
echo "OK"

# 6. 停止并移除 cc-perf 仪表板 LaunchAgent
echo -n "移除 cc-perf 仪表板 LaunchAgent... "
PLIST_PATH="$HOME_DIR/Library/LaunchAgents/com.cc-perf.dashboard.plist"
if [[ -f "$PLIST_PATH" ]]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "OK"
else
    echo "跳过"
fi

# 7. 停止并移除 cc-switch-watch LaunchAgent
echo -n "移除 cc-switch-watch LaunchAgent... "
PLIST_PATH="$HOME_DIR/Library/LaunchAgents/com.cc-perf.switch-watch.plist"
if [[ -f "$PLIST_PATH" ]]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "OK"
else
    echo "跳过"
fi

# 8. 停止后台守护进程
echo -n "停止 cc-switch-watch 守护进程... "
PID_FILE="$HOME_DIR/.claude/timing/.cc-switch-watch.pid"
if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    echo "OK"
else
    echo "跳过"
fi

echo ""
echo "cc-perf 已卸载。"
echo "计时数据仍在: $TIMING_DIR （如需清理请手动删除）"
echo "cc-switch-watch 已停止并移除"
