#!/bin/bash
# cc-perf 一键安装脚本
# 用法: bash install.sh [--force]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FORCE=false
[[ "$1" == "--force" ]] && FORCE=true

CC_PERF_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$HOME"
SETTINGS_FILE="$HOME_DIR/.claude/settings.json"
SETTINGS_LOCAL="$HOME_DIR/.claude/settings.local.json"
INSTALLED_PLUGINS="$HOME_DIR/.claude/plugins/installed_plugins.json"
CACHE_DIR="$HOME_DIR/.claude/plugins/cache/local/cc-perf"
CACHE_LINK="$CACHE_DIR/1.0.0"

echo -e "${GREEN}=== cc-perf 一键安装 ===${NC}"
echo "插件路径: $CC_PERF_DIR"
echo ""

# === 1. 依赖检查 ===
echo -n "检查 Node.js... "
if command -v node &>/dev/null; then
    echo -e "${GREEN}$(node -v)${NC}"
else
    echo -e "${RED}未安装${NC}"
    echo "请先安装 Node.js: https://nodejs.org"
    exit 1
fi

# === 2. 创建数据目录 ===
echo -n "创建数据目录... "
mkdir -p "$HOME_DIR/.claude/timing/.in-flight"
echo -e "${GREEN}OK${NC}"

# === 3. 注册插件 ===
echo -n "注册插件... "
mkdir -p "$CACHE_DIR"

# 符号链接
if [[ -L "$CACHE_LINK" ]] || [[ -d "$CACHE_LINK" ]]; then
    if $FORCE; then
        rm -rf "$CACHE_LINK"
    else
        echo -e "${YELLOW}已存在，跳过${NC}"
    fi
fi
[[ ! -e "$CACHE_LINK" ]] && ln -sfn "$CC_PERF_DIR" "$CACHE_LINK"

# installed_plugins.json
if [[ -f "$INSTALLED_PLUGINS" ]]; then
    node -e "
const fs=require('fs');
const data=JSON.parse(fs.readFileSync('$INSTALLED_PLUGINS','utf8'));
data.plugins['cc-perf@local']=[{scope:'user',installPath:'$CACHE_LINK',version:'1.0.0',installedAt:new Date().toISOString(),lastUpdated:new Date().toISOString()}];
fs.writeFileSync('$INSTALLED_PLUGINS',JSON.stringify(data,null,2));
" 2>/dev/null || true
fi
echo -e "${GREEN}OK${NC}"

# === 4. 启用插件 ===
echo -n "启用插件... "
if [[ -f "$SETTINGS_FILE" ]]; then
    node -e "
const fs=require('fs');
const data=JSON.parse(fs.readFileSync('$SETTINGS_FILE','utf8'));
if(!data.enabledPlugins) data.enabledPlugins={};
data.enabledPlugins['cc-perf@local']=true;
fs.writeFileSync('$SETTINGS_FILE',JSON.stringify(data,null,2));
" 2>/dev/null || true
fi
echo -e "${GREEN}OK${NC}"

# === 5. 配置 hooks（直接合并到 settings.json） ===
echo -n "配置 hooks... "
if [[ -f "$SETTINGS_FILE" ]]; then
    node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('$SETTINGS_FILE', 'utf8'));
if (!data.hooks) data.hooks = {};

const PRE = {
  matcher: '*',
  hooks: [{ type: 'command', command: 'node \"$CC_PERF_DIR/hooks/pre-tool-use.js\"', timeout: 5 }]
};
const POST = {
  matcher: '*',
  hooks: [{ type: 'command', command: 'node \"$CC_PERF_DIR/hooks/post-tool-use.js\"', timeout: 5 }]
};

function hasCCPerf(arr) {
  return arr && arr.some(h => h.hooks && h.hooks[0] && h.hooks[0].command && h.hooks[0].command.includes('cc-perf'));
}

if (!data.hooks.PreToolUse) data.hooks.PreToolUse = [];
if (!hasCCPerf(data.hooks.PreToolUse)) data.hooks.PreToolUse.push(PRE);

if (!data.hooks.PostToolUse) data.hooks.PostToolUse = [];
if (!hasCCPerf(data.hooks.PostToolUse)) data.hooks.PostToolUse.push(POST);

if (!data.hooks.PostToolUseFailure) data.hooks.PostToolUseFailure = [];
if (!hasCCPerf(data.hooks.PostToolUseFailure)) data.hooks.PostToolUseFailure.push(POST);

fs.writeFileSync('$SETTINGS_FILE', JSON.stringify(data, null, 2));
" 2>/dev/null || true
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}settings.json 不存在${NC}"
fi

# === 6. 注册 /perf 命令（全局，不依赖插件 symlink） ===
echo -n "注册 /perf 命令... "
GLOBAL_COMMANDS="$HOME_DIR/.claude/commands"
mkdir -p "$GLOBAL_COMMANDS"
# 复制并替换路径占位符为绝对路径
cp "$CC_PERF_DIR/commands/perf.md" "$GLOBAL_COMMANDS/perf.md"
node -e "
const fs=require('fs');
let c=fs.readFileSync('$GLOBAL_COMMANDS/perf.md','utf8');
c=c.replaceAll('\${CLAUDE_PLUGIN_ROOT}','$CC_PERF_DIR');
fs.writeFileSync('$GLOBAL_COMMANDS/perf.md',c);
" 2>/dev/null || true
echo -e "${GREEN}OK${NC}"

# === 7. 注册 launchd 服务 ===
echo -n "注册 launchd 服务... "
NODE_PATH=$(which node)
PLIST_SRC="$CC_PERF_DIR/scripts/com.cc-perf.dashboard.plist"
PLIST_DST="$HOME_DIR/Library/LaunchAgents/com.cc-perf.dashboard.plist"
SERVER_PATH="$CC_PERF_DIR/scripts/server.js"

if [[ -f "$PLIST_SRC" ]]; then
    # 确保 LaunchAgents 目录存在
    mkdir -p "$HOME_DIR/Library/LaunchAgents"

    # 生成 plist，替换占位符
    sed -e "s|/usr/local/bin/node|$NODE_PATH|g" \
        -e "s|__SERVER_PATH__|$SERVER_PATH|g" \
        "$PLIST_SRC" > "$PLIST_DST"

    # 如果服务已在运行，先卸载再重新加载
    if launchctl list "com.cc-perf.dashboard" &>/dev/null; then
        launchctl unload "$PLIST_DST" 2>/dev/null || true
    fi

    # 加载服务
    launchctl load "$PLIST_DST" 2>/dev/null

    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}plist 模板不存在，跳过${NC}"
fi

# === 8. 验证 ===
echo ""
echo -e "${GREEN}=== 验证安装 ===${NC}"

echo -n "Hook 脚本语法... "
node -c "$CC_PERF_DIR/hooks/pre-tool-use.js" 2>/dev/null && echo -e "${GREEN}pre ✓${NC}"
node -c "$CC_PERF_DIR/hooks/post-tool-use.js" 2>/dev/null && echo -e "${GREEN}post ✓${NC}"

echo -n "端到端测试... "
echo '{"session_id":"install","tool_use_id":"toolu_install","tool_name":"Bash","tool_input":{"command":"install test"}}' | node "$CC_PERF_DIR/hooks/pre-tool-use.js" > /dev/null
echo '{"session_id":"install","tool_use_id":"toolu_install","tool_name":"Bash","tool_input":{"command":"install test"}}' | node "$CC_PERF_DIR/hooks/post-tool-use.js" > /dev/null
rm -f "$HOME_DIR/.claude/timing/install.jsonl"
echo -e "${GREEN}OK${NC}"

# === 完成 ===
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  cc-perf 安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  服务已作为 LaunchAgent 注册，将开机自启并常驻运行"
echo ""
echo "  用法:"
echo "    /perf          - 显示当前会话耗时摘要"
echo "    /perf start    - 打开仪表板（服务已自动启动）"
echo "    /perf stop     - 暂停仪表板服务"
echo "    /perf status   - 查看统计摘要"
echo ""
echo "  仪表板: http://127.0.0.1:3100"
echo "  数据目录: ~/.claude/timing/"
echo "  卸载: bash uninstall.sh"
