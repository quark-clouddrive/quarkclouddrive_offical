#!/usr/bin/env node
/**
 * dedup.js — 按「文件名|字节大小」找重复，生成安全移动计划
 *
 * 用法：
 *   node dedup.js --in ./out/all-items.json --out ./dup-plan.json [--keep-pattern "^(?!我的备份)"]
 *
 * 安全保证：每个重复组至少保留一份副本。
 *   --keep-pattern 是正则，命中的位置（folder 字段）优先保留；
 *   若全部副本都命中，则保留第一个。
 * 产出：plan 数组 [{fid, from, destHint}] + 可释放空间统计打印到 stdout。
 */
const fs = require('fs');
const path = require('path');

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : def;
}
const inFile = path.resolve(arg('--in', './out/all-items.json'));
const outFile = path.resolve(arg('--out', './dup-plan.json'));
const keepPattern = new RegExp(arg('--keep-pattern', '^(?!我的备份)').replace(/^\/|\/$/g, '') || '(?!.*)');

if (!fs.existsSync(inFile)) { console.error(`找不到 ${inFile}`); process.exit(1); }
const all = require(inFile);

// 分组（仅文件、size>0）
const groups = {};
for (const o of all) {
  if (o.type === '0' || !o.size) continue;
  const k = `${o.filename}|${o.size}`;
  (groups[k] = groups[k] || []).push(o);
}

const plan = [];
let files = 0, bytes = 0;
let dupGroups = 0;

for (const [k, items] of Object.entries(groups)) {
  if (items.length < 2) continue;
  dupGroups++;
  // 保留策略
  const keepers = items.filter(o => keepPattern.test(o.folder));
  const keep = keepers.length ? keepers : items.slice(0, 1);
  const keepSet = new Set(keep.map(o => o.fid));
  for (const o of items) {
    if (keepSet.has(o.fid)) continue;
    plan.push({ fid: o.fid, from: o.folder ? `${o.folder}/${o.filename}` : o.filename, destHint: '_待清理' });
    files++;
    bytes += o.size;
  }
}

console.log(`重复组：${dupGroups} 组`);
console.log(`多余副本：${files} 个`);
console.log(`可释放：${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`);
console.log(`计划写入：${outFile}`);

fs.writeFileSync(outFile, JSON.stringify(plan, null, 1));
