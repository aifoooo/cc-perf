#!/usr/bin/env node
/**
 * cc-perf 仪表板服务器
 *
 * 零运行时依赖，仅使用 Node.js 内置模块。
 * 端口: 3100，监听 127.0.0.1
 * 通过 launchd 常驻运行
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = 3100;
const HOST = '127.0.0.1';
const TIMING_DIR = path.join(os.homedir(), '.claude', 'timing');
const PUBLIC_DIR = path.join(__dirname, '..', 'public');
const PID_FILE = path.join(TIMING_DIR, '.server.pid');

// 确保数据目录存在
fs.mkdirSync(TIMING_DIR, { recursive: true });

// MIME 类型映射
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

// === API 处理 ===

function listSessions() {
  const sessions = [];
  try {
    const files = fs.readdirSync(TIMING_DIR);
    for (const f of files) {
      if (!f.endsWith('.jsonl')) continue;
      const filePath = path.join(TIMING_DIR, f);
      const stat = fs.statSync(filePath);
      sessions.push({
        id: f.replace('.jsonl', ''),
        file: f,
        size: stat.size,
        mtime: stat.mtimeMs,
      });
    }
    // 按修改时间倒序
    sessions.sort((a, b) => b.mtime - a.mtime);
  } catch {}
  return sessions;
}

function readSession(sessionId) {
  const slug = sessionId.replace(/[^a-zA-Z0-9_-]/g, '_');
  const filePath = path.join(TIMING_DIR, `${slug}.jsonl`);
  const entries = [];
  try {
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, 'utf8');
      for (const line of content.trim().split('\n')) {
        if (line) entries.push(JSON.parse(line));
      }
    }
  } catch {}
  return entries;
}

function parseRoute(url) {
  const parsed = new URL(url, 'http://localhost');
  return {
    pathname: parsed.pathname,
    params: Object.fromEntries(parsed.searchParams),
  };
}

function jsonResponse(res, data, status = 200) {
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(JSON.stringify(data));
}

// === 静态文件服务 ===

function serveStatic(res, filePath) {
  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME[ext] || 'application/octet-stream';

  try {
    const content = fs.readFileSync(filePath);
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(content);
  } catch {
    res.writeHead(404);
    res.end('Not Found');
  }
}

// === 服务器 ===

const server = http.createServer((req, res) => {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const { pathname, params } = parseRoute(req.url);

  // API 路由
  if (pathname === '/api/sessions') {
    const sessions = listSessions();
    // 为每个 session 附加条目计数和总耗时
    const enriched = sessions.map((s) => {
      const entries = readSession(s.id);
      const totalMs = entries.reduce((sum, e) => sum + (e.duration_ms || 0), 0);
      const toolTypes = [...new Set(entries.map((e) => e.tool_name))];
      return {
        ...s,
        entry_count: entries.length,
        total_ms: totalMs,
        tool_types: toolTypes,
      };
    });
    return jsonResponse(res, enriched);
  }

  if (pathname.startsWith('/api/session/')) {
    const pathParts = pathname.replace('/api/session/', '').split('/');
    const sessionId = pathParts[0];

    // GET /api/session/:id/since/:timestamp
    if (pathParts[1] === 'since' && pathParts[2]) {
      const since = parseInt(pathParts[2], 10);
      const entries = readSession(sessionId);
      const filtered = entries.filter((e) => e.end > since);
      return jsonResponse(res, filtered);
    }

    // GET /api/session/:id
    const entries = readSession(sessionId);
    return jsonResponse(res, entries);
  }

  if (pathname === '/api/summary') {
    const sessions = listSessions();
    let totalCalls = 0;
    let totalMs = 0;
    const byTool = {};

    for (const s of sessions) {
      const entries = readSession(s.id);
      for (const e of entries) {
        totalCalls++;
        totalMs += e.duration_ms || 0;
        if (!byTool[e.tool_name]) {
          byTool[e.tool_name] = { count: 0, total_ms: 0, max_ms: 0, min_ms: Infinity };
        }
        byTool[e.tool_name].count++;
        byTool[e.tool_name].total_ms += e.duration_ms || 0;
        byTool[e.tool_name].max_ms = Math.max(byTool[e.tool_name].max_ms, e.duration_ms || 0);
        byTool[e.tool_name].min_ms = Math.min(byTool[e.tool_name].min_ms, e.duration_ms || 0);
      }
    }

    return jsonResponse(res, {
      total_calls: totalCalls,
      total_ms: totalMs,
      session_count: sessions.length,
      by_tool: byTool,
    });
  }

  // 静态文件
  if (pathname === '/' || pathname === '/index.html') {
    return serveStatic(res, path.join(PUBLIC_DIR, 'index.html'));
  }

  // 其他静态资源
  const staticPath = path.join(PUBLIC_DIR, pathname);
  if (fs.existsSync(staticPath) && fs.statSync(staticPath).isFile()) {
    return serveStatic(res, staticPath);
  }

  // 404
  res.writeHead(404);
  res.end('Not Found');
});

function cleanup() {
  try {
    if (fs.existsSync(PID_FILE)) fs.unlinkSync(PID_FILE);
  } catch {}
}

// 检查是否已有服务器在运行
if (fs.existsSync(PID_FILE)) {
  try {
    const oldPid = parseInt(fs.readFileSync(PID_FILE, 'utf8'), 10);
    try {
      process.kill(oldPid, 0); // 检查进程是否存在
      console.log(`[cc-perf] 检测到已有服务器运行中 (PID: ${oldPid})，正在关闭...`);
      process.kill(oldPid, 'SIGTERM');
    } catch {
      // 进程不存在，清理僵尸 PID 文件
      fs.unlinkSync(PID_FILE);
    }
  } catch {}
}

server.listen(PORT, HOST, () => {
  // 写入 PID 文件
  try {
    fs.writeFileSync(PID_FILE, String(process.pid));
  } catch {}

  console.log(`\ncc-perf 仪表板已启动: http://${HOST}:${PORT}\n`);
});

// 优雅退出
process.on('SIGINT', () => {
  cleanup();
  process.exit(0);
});
process.on('SIGTERM', () => {
  cleanup();
  process.exit(0);
});
