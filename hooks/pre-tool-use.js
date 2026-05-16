/**
 * cc-perf PreToolUse Hook
 *
 * 在每次工具调用前记录起始时间，写入 ~/.claude/timing/.in-flight/<tool_use_id>.json
 * 用于与 post-tool-use.js 协同计算工具执行耗时
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const TIMING_DIR = path.join(os.homedir(), '.claude', 'timing');
const IN_FLIGHT_DIR = path.join(TIMING_DIR, '.in-flight');
const MAX_SUMMARY_LEN = 120;
const MAX_STDIN = 1024 * 1024; // 1MB

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
    // JSON 解析失败，静默透传
    process.stdout.write(raw);
    return;
  }

  const toolUseId = input.tool_use_id;
  const toolName = input.tool_name;
  const sessionId = input.session_id || process.env.CLAUDE_SESSION_ID || 'unknown';
  const toolInput = input.tool_input;

  // 缺少关键字段，静默跳过
  if (!toolUseId || !toolName) {
    process.stdout.write(raw);
    return;
  }

  // 生成工具调用摘要
  const summary = buildSummary(toolName, toolInput);

  // 写入 in-flight 文件
  const record = {
    session_id: sessionId,
    tool_name: toolName,
    tool_input_summary: summary,
    start: Date.now(),
  };

  try {
    fs.mkdirSync(IN_FLIGHT_DIR, { recursive: true });
    // 清理文件名中的不安全字符（tool_use_id 通常只含字母数字和下划线）
    const safeId = toolUseId.replace(/[^a-zA-Z0-9_-]/g, '_');
    const filePath = path.join(IN_FLIGHT_DIR, `${safeId}.json`);
    fs.writeFileSync(filePath, JSON.stringify(record));
  } catch (e) {
    // 写入失败不阻断，仅输出警告到 stderr
    process.stderr.write(`[cc-perf] pre-tool-use: 写入失败 ${e.message}\n`);
  }

  // 透传原始输入
  process.stdout.write(raw);
});

function buildSummary(toolName, toolInput) {
  if (!toolInput) return '';

  switch (toolName) {
    case 'Bash': {
      const cmd =
        typeof toolInput.command === 'string' ? toolInput.command : JSON.stringify(toolInput);
      return cmd.length > MAX_SUMMARY_LEN
        ? cmd.substring(0, MAX_SUMMARY_LEN) + '...'
        : cmd.replace(/\n/g, ' ');
    }
    case 'Read':
    case 'Edit':
    case 'Write':
      return typeof toolInput.file_path === 'string'
        ? toolInput.file_path
        : JSON.stringify(toolInput).substring(0, MAX_SUMMARY_LEN);
    case 'Glob':
      return typeof toolInput.pattern === 'string'
        ? `glob: ${toolInput.pattern}`
        : '';
    case 'Grep':
      return typeof toolInput.pattern === 'string'
        ? `grep: ${toolInput.pattern}`
        : '';
    case 'Agent':
      return typeof toolInput.description === 'string'
        ? `agent: ${toolInput.description}`
        : typeof toolInput.prompt === 'string'
          ? `agent: ${toolInput.prompt.substring(0, MAX_SUMMARY_LEN)}`
          : 'agent';
    case 'WebFetch':
      return typeof toolInput.url === 'string' ? `fetch: ${toolInput.url}` : 'fetch';
    case 'WebSearch':
      return typeof toolInput.query === 'string' ? `search: ${toolInput.query}` : 'search';
    default:
      return JSON.stringify(toolInput).substring(0, MAX_SUMMARY_LEN);
  }
}
