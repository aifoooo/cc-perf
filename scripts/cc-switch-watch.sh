#!/bin/bash
# cc-switch-watch.sh
# 监听 settings.json 变化，自动恢复 cc-perf 插件配置
#
# 用法:
#   ./cc-switch-watch.sh          # 前台运行（测试用）
#   ./cc-switch-watch.sh --daemon # 后台守护进程
#
# 安装为 LaunchAgent (推荐):
#   ./cc-switch-watch.sh --install
#   ./cc-switch-watch.sh --uninstall

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_PERF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SCRIPT="$CC_PERF_DIR/install.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"
PID_FILE="$HOME/.claude/timing/.cc-switch-watch.pid"
LOG_FILE="$HOME/.claude/timing/cc-switch-watch.log"

# 检查 cc-perf 配置是否存在
check_cc_perf_config() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        return 1
    fi

    # 检查 enabledPlugins 中是否有 cc-perf
    if ! grep -q '"cc-perf@local"' "$SETTINGS_FILE" 2>/dev/null; then
        return 1
    fi

    # 检查 hooks 中是否有 cc-perf
    if ! grep -q 'cc-perf/hooks/pre-tool-use.js' "$SETTINGS_FILE" 2>/dev/null; then
        return 1
    fi

    return 0
}

# 恢复 cc-perf 配置
restore_cc_perf() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] 检测到 cc-perf 配置丢失，正在恢复..." >> "$LOG_FILE"

    if [[ -f "$INSTALL_SCRIPT" ]]; then
        bash "$INSTALL_SCRIPT" --force >> "$LOG_FILE" 2>&1
        echo "[$timestamp] cc-perf 配置已恢复" >> "$LOG_FILE"
    else
        echo "[$timestamp] 错误: install.sh 不存在" >> "$LOG_FILE"
    fi
}

# 使用 fswatch 监听文件变化
watch_with_fswatch() {
    if ! command -v fswatch &>/dev/null; then
        echo "错误: 需要安装 fswatch"
        echo "运行: brew install fswatch"
        exit 1
    fi

    echo "开始监听 $SETTINGS_FILE ..."
    echo "PID: $$"
    echo $$ > "$PID_FILE"

    # 监听 settings.json 的修改事件
    fswatch -0 --event=Updated "$SETTINGS_FILE" | while read -d "" event; do
        sleep 0.5  # 等待文件写入完成
        if ! check_cc_perf_config; then
            restore_cc_perf
        fi
    done
}

# 使用轮询方式监听（不需要额外依赖）
watch_with_polling() {
    echo "开始监听 $SETTINGS_FILE (轮询模式)..."
    echo "PID: $$"
    echo $$ > "$PID_FILE"

    local last_mtime=""

    while true; do
        if [[ -f "$SETTINGS_FILE" ]]; then
            local current_mtime=$(stat -f %m "$SETTINGS_FILE" 2>/dev/null || stat -c %Y "$SETTINGS_FILE" 2>/dev/null)

            if [[ "$current_mtime" != "$last_mtime" ]]; then
                last_mtime="$current_mtime"
                sleep 0.5  # 等待文件写入完成

                if ! check_cc_perf_config; then
                    restore_cc_perf
                fi
            fi
        fi

        sleep 1
    done
}

# 安装为 LaunchAgent
install_launchagent() {
    local plist_path="$HOME/Library/LaunchAgents/com.cc-perf.switch-watch.plist"

    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cc-perf.switch-watch</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/cc-switch-watch.sh</string>
        <string>--polling</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF

    launchctl load "$plist_path" 2>/dev/null || true
    echo "LaunchAgent 已安装: $plist_path"
    echo "日志文件: $LOG_FILE"
    echo ""
    echo "管理命令:"
    echo "  停止: launchctl unload $plist_path"
    echo "  启动: launchctl load $plist_path"
    echo "  状态: launchctl list | grep cc-perf"
}

# 卸载 LaunchAgent
uninstall_launchagent() {
    local plist_path="$HOME/Library/LaunchAgents/com.cc-perf.switch-watch.plist"

    if [[ -f "$plist_path" ]]; then
        launchctl unload "$plist_path" 2>/dev/null || true
        rm -f "$plist_path"
        echo "LaunchAgent 已卸载"
    else
        echo "LaunchAgent 未安装"
    fi
}

# 停止后台进程
stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            echo "已停止进程 $pid"
        fi
        rm -f "$PID_FILE"
    fi
}

# 显示帮助
show_help() {
    cat << EOF
cc-switch-watch - 监听 cc-switch 配置切换，自动恢复 cc-perf 插件配置

用法:
  $0              前台运行（使用 fswatch）
  $0 --polling    前台运行（轮询模式，无需依赖）
  $0 --install    安装为 LaunchAgent（开机自启）
  $0 --uninstall  卸载 LaunchAgent
  $0 --stop       停止后台进程
  $0 --status     显示状态
  $0 --help       显示帮助

依赖:
  fswatch (可选): brew install fswatch

日志文件:
  $LOG_FILE
EOF
}

# 显示状态
show_status() {
    echo "=== cc-switch-watch 状态 ==="
    echo ""

    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "运行中: PID $pid"
        else
            echo "已停止 (僵尸 PID 文件)"
        fi
    else
        echo "未运行"
    fi

    echo ""
    echo "cc-perf 配置状态:"
    if check_cc_perf_config; then
        echo "  ✓ 配置正常"
    else
        echo "  ✗ 配置缺失"
    fi

    echo ""
    echo "LaunchAgent:"
    local plist_path="$HOME/Library/LaunchAgents/com.cc-perf.switch-watch.plist"
    if [[ -f "$plist_path" ]]; then
        echo "  已安装: $plist_path"
    else
        echo "  未安装"
    fi
}

# 主入口
case "${1:-}" in
    --daemon)
        watch_with_fswatch &
        echo "后台运行中，PID: $!"
        ;;
    --polling)
        watch_with_polling
        ;;
    --install)
        install_launchagent
        ;;
    --uninstall)
        uninstall_launchagent
        ;;
    --stop)
        stop_daemon
        ;;
    --status)
        show_status
        ;;
    --help|-h)
        show_help
        ;;
    *)
        # 默认使用 fswatch，如果没有安装则使用轮询
        if command -v fswatch &>/dev/null; then
            watch_with_fswatch
        else
            echo "提示: 安装 fswatch 可获得更好的性能 (brew install fswatch)"
            echo "使用轮询模式..."
            watch_with_polling
        fi
        ;;
esac
