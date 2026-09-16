#!/usr/bin/env node
/**
 * scan.js — 递归扫描夸克网盘，产出全量文件清单 all-items.json
 *
 * 用法：
 *   node scan.js --out ./scan-out [--root-fid 0] [--max-depth 4]
 *
 * 环境变量（见 README §5）：
 *   QUARK_CLI       CLI 绝对路径（默认 ~/.kimi-code/skills/quarkclouddrive/scripts/quark-drive.cjs）
 *   QUARK_WORKDIR   触发 kimiwork 识别的工作目录（默认 ~/.kimi-work）
 *   QUARK_SESSION_ID 会话 ID（默认自动生成）
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : def;
}
const outDir = path.resolve(arg('--out', './scan-out'));
const rootFid = arg('--root-fid', '0');
const maxDepth = parseInt(arg('--max-depth', '4'), 10);

const CLI = process.env.QUARK_CLI || path.join(os.homedir(), '.kimi-code', 'skills', 'quarkclouddrive', 'scripts', 'quark-drive.cjs');
const WORKDIR = process.env.QUARK_WORKDIR || path.join(os.homedir(), '.kimi-work');
const SESSION = process.env.QUARK_SESSION_ID || `${Math.floor(Date.now() / 1000)}-${Math.random().toString(36).slice(2, 8)}`;

fs.mkdirSync(outDir, { recursive: true });

function runCli(args) {
  const r = spawnSync('node', [CLI, ...args, '--session-id', SESSION, '--session-input', '全盘扫描'], {
    cwd: WORKDIR, encoding: 'utf8', timeout: 120000,
  });
  if (r.status !== 0 || !r.stdout) return null;
  return r.stdout.trim().split('\n').filter(Boolean).map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
}

function browse(fid) {
  const lines = runCli(['browse', '--parent-fid', fid, '--all']);
  if (!lines) return [];
  const art = lines.find(l => l.type === 'artifact');
  if (!art) return [];
  let out = [];
  try {
    out = fs.readFileSync(art.data.file_path, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse);
  } catch { }
  return out;
}

// 逐层扫描
const all = [];
const queue = [{ fid: rootFid, folder: '' }];
const seen = new Set();
let batchNo = 0;

function ingest(items, folder) {
  for (const o of items) {
    all.push({ folder, fid: o.fid, filename: o.filename, size: o.size, type: o.file_type, updated: o.updated_at });
    if (o.file_type === '0' && !seen.has(o.fid)) {
      seen.add(o.fid);
      queue.push({ fid: o.fid, folder: folder ? `${folder}/${o.filename}` : o.filename });
    }
  }
}

// 逐层处理，直到 maxDepth 层
while (queue.length) {
  const { fid, folder } = queue.shift();
  const depth = folder ? folder.split('/').length : 0;
  if (depth >= maxDepth) continue;
  batchNo++;
  const items = browse(fid);
  ingest(items, folder);
  if (batchNo % 10 === 0 || batchNo <= 3) {
    console.log(`[${batchNo}] ${folder || '(根)'}: ${items.length} 项（累计 ${all.length}）`);
  }
}

fs.writeFileSync(path.join(outDir, 'all-items.json'), JSON.stringify(all, null, 1));
console.log(`\n完成：共 ${all.length} 项 → ${path.join(outDir, 'all-items.json')}`);
