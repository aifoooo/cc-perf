/**
 * cc-perf PostToolUse Hook
 *
 * 在每次工具调用完成后计算耗时，写入 JSONL 日志，输出到终端 stderr
 * 同时清理 .in-flight/ 中超过 30 分钟的孤儿文件
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const TIMING_DIR = path.join(os.homedir(), '.claude', 'timing');
const IN_FLIGHT_DIR = path.join(TIMING_DIR, '.in-flight');
const MAX_STDIN = 1024 * 1024;
const ORPHAN_CLEANUP_MS = 30 * 60 * 1000; // 30 分钟

// 读取 stdin
let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  if (raw.length < MAX_STDIN) raw += chunk.substring(0, MAX_STDIN - raw.length);
});
process.stdin.on('end', () => {
  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    process.stdout.write(raw);
    return;
  }

  const toolUseId = input.tool_use_id;
  const toolName = input.tool_name;
  const sessionId = input.session_id || process.env.CLAUDE_SESSION_ID || 'unknown';
  const toolResult = input.tool_result;

  // 缺少关键字段，静默跳过
  if (!toolUseId || !toolName) {
    process.stdout.write(raw);
    return;
  }

  const safeId = toolUseId.replace(/[^a-zA-Z0-9_-]/g, '_');
  const inFlightPath = path.join(IN_FLIGHT_DIR, `${safeId}.json`);
  const now = Date.now();

  try {
    if (fs.existsSync(inFlightPath)) {
      const record = JSON.parse(fs.readFileSync(inFlightPath, 'utf8'));
      const duration = now - record.start;

      // 判断成功/失败：检查 hook_event_name 是否为 PostToolUseFailure
      const isFailure = input.hook_event_name === 'PostToolUseFailure';
      const success = !isFailure;

      // 写入 JSONL
      const sessionIdClean = record.session_id || sessionId;
      // 用 session_id 的前 8 位作为文件名，避免特殊字符
      const sessionSlug = sessionIdClean.replace(/[^a-zA-Z0-9_-]/g, '_').substring(0, 36);
      const jsonlPath = path.join(TIMING_DIR, `${sessionSlug}.jsonl`);

      const entry = {
        tool_use_id: toolUseId,
        tool_name: record.tool_name || toolName,
        session_id: sessionIdClean,
        start: record.start,
        end: now,
        duration_ms: duration,
        tool_input_summary: record.tool_input_summary || '',
        success,
      };

      fs.mkdirSync(TIMING_DIR, { recursive: true });
      fs.appendFileSync(jsonlPath, JSON.stringify(entry) + '\n');

      // 实时输出到终端
      const durStr = formatDuration(duration);
      const statusIcon = success ? '' : ' ✗';
      process.stderr.write(
        `[cc-perf] ${durStr}${statusIcon}  ${record.tool_name || toolName}  ${record.tool_input_summary || ''}\n`
      );

      // 删除 in-flight 文件
      fs.unlinkSync(inFlightPath);
    }
  } catch (e) {
    process.stderr.write(`[cc-perf] post-tool-use: 错误 ${e.message}\n`);
  }

  // 懒清理孤儿 in-flight 文件
  cleanupOrphans(now);

  // 透传
  process.stdout.write(raw);
});

function formatDuration(ms) {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  const m = Math.floor(ms / 60000);
  const s = Math.round((ms % 60000) / 1000);
  return `${m}m${s}s`;
}

function cleanupOrphans(now) {
  try {
    if (!fs.existsSync(IN_FLIGHT_DIR)) return;
    const files = fs.readdirSync(IN_FLIGHT_DIR);
    for (const file of files) {
      const filePath = path.join(IN_FLIGHT_DIR, file);
      try {
        const stat = fs.statSync(filePath);
        if (now - stat.mtimeMs > ORPHAN_CLEANUP_MS) {
          fs.unlinkSync(filePath);
        }
      } catch {
        // 单个文件清理失败不影响其他
      }
    }
  } catch {
    // 目录读取失败忽略
  }
}
