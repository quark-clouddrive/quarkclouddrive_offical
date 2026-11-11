#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");

const runtimePath = process.argv[2];
if (!runtimePath) {
  console.error("用法: node patches/kimi-code-agent-detection.cjs <quark-drive.cjs>");
  process.exit(1);
}

const expectedVersion = "1.0.25-876f30d";
const expectedSha256 = "b19755822486bd812c76e15de31e9213bccfa2cc6ed1e639c43201e5cf2e07b5";
const detectorAnchor = "function SI(s){return s.env.PI_CODING_AGENT!==void 0}function Ie(";
const mappingAnchor = "[\"pi\",SI]]});function fe(";
const detector = "function KimiCode(s){let{env:e}=s;return e.KIMI_CODE_HOME!==void 0||e.KIMI_CODE_REGION_MARKER!==void 0||e.KIMI_CODE_IDENTITY_SLUG===\"kimi-code\"||zr(s,/\\/\\.kimi-code\\/skills\\//)}";

let source = fs.readFileSync(runtimePath, "utf8");
const hasDetector = source.includes("function KimiCode(s)");
const hasMapping = source.includes("[\"kimicode\",KimiCode]");

if (hasDetector && hasMapping) {
  console.log("Kimi Code Agent 适配已存在，无需重复应用");
  process.exit(0);
}
if (hasDetector || hasMapping || source.includes("kimicode")) {
  throw new Error("检测到不完整的 Kimi Code 适配，拒绝继续修改");
}
if (!source.includes(`WE="${expectedVersion}"`)) {
  throw new Error(`不支持的 CLI 版本，仅支持 ${expectedVersion}`);
}

const actualSha256 = crypto.createHash("sha256").update(source).digest("hex");
if (actualSha256 !== expectedSha256) {
  throw new Error(`CLI 完整性校验失败: ${actualSha256}`);
}

function replaceOnce(input, anchor, replacement) {
  const first = input.indexOf(anchor);
  if (first === -1) {
    throw new Error(`未找到适配锚点: ${anchor}`);
  }
  if (input.indexOf(anchor, first + anchor.length) !== -1) {
    throw new Error(`适配锚点不唯一: ${anchor}`);
  }
  return input.slice(0, first) + replacement + input.slice(first + anchor.length);
}

source = replaceOnce(source, detectorAnchor, `function SI(s){return s.env.PI_CODING_AGENT!==void 0}${detector}function Ie(`);
source = replaceOnce(source, mappingAnchor, "[\"pi\",SI],[\"kimicode\",KimiCode]]});function fe(");

const temporaryPath = `${runtimePath}.kimi-code.tmp`;
fs.writeFileSync(temporaryPath, source, { mode: fs.statSync(runtimePath).mode });
fs.renameSync(temporaryPath, runtimePath);
console.log("Kimi Code Agent 适配已应用");
