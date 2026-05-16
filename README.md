# cc-perf

> Claude Code 每一步耗时透明化——看清瓶颈在哪里。

**问题：** Claude Code 用久了越来越慢，到底卡在模型推理、工具执行、还是网络延迟？只能靠感觉猜。

**解决：** cc-perf 在每一步操作后自动打印耗时，累积数据通过本地 Web 面板可视化，甘特图一眼看出哪一步拖了你后腿。

---

## 组件结构

cc-perf 由两个独立组件构成：

| 组件 | 安装 | 卸载 | 说明 |
|------|------|------|------|
| **cc-perf 核心** | `bash install.sh` | `bash uninstall.sh` | 插件 + hooks + /perf 命令 |
| **cc-switch-watch** | `./scripts/cc-switch-watch.sh --install` | `./scripts/cc-switch-watch.sh --uninstall` 或 `uninstall.sh` | 监听 cc-switch 切换，自动恢复配置（可选） |

---

## 快速开始

### 1. 安装 cc-perf 核心

```bash
bash install.sh
```

脚本自动完成：

1. **注册插件** — symlink + installed_plugins.json
2. **启用插件** — settings.json enabledPlugins
3. **配置 hooks** — settings.json 中合并 PreToolUse/PostToolUse hooks
4. **注册 /perf 命令** — 复制到 `~/.claude/commands/`
5. **验证** — 端到端测试

> 安装后**重启 Claude Code**（新会话），hooks 和 `/perf` 才会同时生效。

### 2. 可选：安装 cc-switch-watch（如果你用 cc-switch）

```bash
# 方式 1：后台守护进程（轮询模式）
./scripts/cc-switch-watch.sh --polling

# 方式 2：安装为 LaunchAgent（开机自启）
./scripts/cc-switch-watch.sh --install
```

cc-switch 切换配置时会覆盖 `settings.json`，导致 cc-perf 配置丢失。cc-switch-watch 通过监听文件变化，自动运行 `install.sh --force` 恢复配置。

### 3. 可选：启动 Web 仪表板

```bash
# 方式 1：斜杠命令（在 Claude Code 中）
/perf start

# 方式 2：直接启动
node scripts/server.js
```

浏览器打开 `http://127.0.0.1:3100`。

---

## 效果

### 终端实时反馈

每步操作完成后终端直接显示耗时，不必等，不用查：

```
[cc-perf] 2.3s  Bash: pnpm tsc --noEmit
[cc-perf] 0.1s  Read: src/main/ipc/goals.ts
[cc-perf] 15.6s  Agent: code-reviewer
[cc-perf] 0.2s  Edit: src/renderer/components/GoalCard.tsx
```

黑色背景上看着，哪步慢一目了然。

### Web 仪表板

| 面板 | 回答什么问题 |
|------|-------------|
| 概览卡片 | 这次会话总共花了多少时间？调用了多少次工具？ |
| 甘特图 | 哪一步耗时最长？并行执行情况如何？ |
| 环形图 | Bash/Agent/Read 各占多少比例？ |
| Top-15 表格 | 最慢的 15 步是哪些？具体在做什么？ |

### 诊断场景举例

- **"Agent 启动太慢"** → 甘特图里 Agent 条很长，点一下看是哪个 agent 耗时
- **"build 检查卡很久"** → Top-15 表格里 `pnpm tsc --noEmit` 出现在第 1 名
- **"到底在等什么"** → 实时输出告诉你当前卡在哪个 Bash 命令上
- **"hooks 开销多大"** → 环形图看各工具占比，如果 Script/Lint 占比异常，说明 hooks 过重

---

## 命令参考

### cc-perf 核心

| 命令 | 作用 |
|------|------|
| `bash install.sh` | 一键安装 |
| `bash uninstall.sh` | 一键卸载（同时清理 cc-switch-watch） |
| `/perf` | 当前会话耗时摘要 |
| `/perf start` | 启动仪表板 + 打开浏览器 |
| `/perf stop` | 停止仪表板 |

### cc-switch-watch

| 命令 | 作用 |
|------|------|
| `./scripts/cc-switch-watch.sh` | 前台运行（使用 fswatch） |
| `./scripts/cc-switch-watch.sh --polling` | 前台运行（轮询模式，无需额外依赖） |
| `./scripts/cc-switch-watch.sh --install` | 安装为 LaunchAgent（开机自启） |
| `./scripts/cc-switch-watch.sh --uninstall` | 卸载 LaunchAgent |
| `./scripts/cc-switch-watch.sh --stop` | 停止守护进程 |
| `./scripts/cc-switch-watch.sh --status` | 查看状态 |
| `./scripts/cc-switch-watch.sh --help` | 显示帮助 |

---

## 数据

所有数据在 `~/.claude/timing/`，纯 JSONL 格式，可以直接分析：

```
~/.claude/timing/
├── .in-flight/              # 正在执行的调用（临时）
│   └── <tool_use_id>.json
├── <session-id>.jsonl       # 每行一条：{tool_name, duration_ms, ...}
└── .cc-switch-watch.pid     # cc-switch-watch 进程 ID
```

磁盘占用约 200 字节/条，1000 次调用 ≈ 200KB，可忽略。不需要时直接 `rm -rf ~/.claude/timing/` 即可。

---

## 项目结构

```
cc-perf/
├── install.sh                    # cc-perf 核心安装
├── uninstall.sh                  # 整体卸载（cc-perf + cc-switch-watch）
├── .claude-plugin/plugin.json    # 插件清单
├── hooks/
│   ├── pre-tool-use.js           # 记录起始时间
│   └── post-tool-use.js          # 计算耗时 + 输出
├── scripts/
│   ├── server.js                 # Web 仪表板（零依赖 HTTP）
│   ├── start-dashboard.sh        # 后台启动仪表板
│   ├── stop-dashboard.sh         # 停止仪表板
│   └── cc-switch-watch.sh        # 监听 cc-switch 配置变化（可选）
├── public/
│   └── index.html                # 仪表板页面（Chart.js CDN）
└── commands/
    └── perf.md                   # /perf 斜杠命令
```

---

## License

MIT