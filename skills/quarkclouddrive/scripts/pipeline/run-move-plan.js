#!/usr/bin/env node
/**
 * run-move-plan.js — 执行移动计划，批量失败自动降级逐个移动
 *
 * 用法：
 *   node run-move-plan.js --plan ./dup-plan.json --target-fid <目标目录fid>
 *
 * 环境变量同 scan.js（QUARK_CLI / QUARK_WORKDIR / QUARK_SESSION_ID）。
 * 计划格式：[{fid, from}]，--plan 指定。按目标分组分批（≤50/批）。
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : def;
}
const planFile = path.resolve(arg('--plan', './dup-plan.json'));
const targetFid = arg('--target-fid', '');
if (!targetFid) { console.error('缺少 --target-fid'); process.exit(1); }

const CLI = process.env.QUARK_CLI || path.join(os.homedir(), '.kimi-code', 'skills', 'quarkclouddrive', 'scripts', 'quark-drive.cjs');
const WORKDIR = process.env.QUARK_WORKDIR || path.join(os.homedir(), '.kimi-work');
const SESSION = process.env.QUARK_SESSION_ID || `${Math.floor(Date.now() / 1000)}-${Math.random().toString(36).slice(2, 8)}`;

const plan = JSON.parse(fs.readFileSync(planFile, 'utf8'));
console.log(`计划共 ${plan.length} 项，目标目录 fid=${targetFid}`);

function move(fids) {
  const args = ['move', ...fids, '--target-fid', targetFid, '--session-id', SESSION, '--session-input', '执行整理移动计划'];
  const r = spawnSync('node', [CLI, ...args], { cwd: WORKDIR, encoding: 'utf8', timeout: 120000 });
  if (r.status !== 0) return false;
  return (r.stdout || '').includes('"code":0');
}

// 分批：批量优先，失败整批降级逐个
let ok = 0;
const fail = [];
const BATCH = 50;
for (let i = 0; i < plan.length; i += BATCH) {
  const slice = plan.slice(i, i + BATCH);
  process.stdout.write(`批次 ${Math.floor(i / BATCH) + 1}/${Math.ceil(plan.length / BATCH)}（${slice.length}项）: `);
  try {
    if (move(slice.map(o => o.fid))) { console.log('批量成功'); ok += slice.length; continue; }
  } catch { }
  let batchOk = 0;
  for (const o of slice) {
    try { if (move([o.fid])) { ok++; batchOk++; } else fail.push(o.from); }
    catch { fail.push(o.from); }
  }
  console.log(`降级逐个 ${batchOk}/${slice.length}`);
}

console.log(`\n成功 ${ok}/${plan.length}，失败 ${fail.length}`);
if (fail.length) { console.log('失败项：'); fail.forEach(f => console.log('  ' + f)); }
