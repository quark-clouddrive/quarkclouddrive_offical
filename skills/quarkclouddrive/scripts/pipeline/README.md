# 夸克网盘整理 Pipeline 交接文档

> 由 Kimi Code 在 2026-09 的一次网盘整理实战中沉淀。目标读者：任何要复用这套流程的 AI agent 或开发者。

## 1. 这套 Pipeline 是什么

对夸克网盘做四件事的标准流程：

1. **摸底** — 递归扫描全盘（或指定子树），产出统一的全量文件清单 `all-items.json`
2. **查重** — 按「文件名 + 字节大小」分组找重复，生成「每组至少保留一份」的安全移动计划
3. **隔离清理** — CLI 没有删除 API，所有待删内容统一移入 `_待清理` 隔离夹，最后由人在夸克 App 里一键删除
4. **归置** — 建分类文件夹，按预检计划批量移动（批量失败自动降级为逐个移动）

可选第五步：**AI 相册整理**（`organize` 命令，服务端按时间/主题/地点聚类，仅支持图片和视频，见 §6）。

## 2. 组件清单与安装

| 组件 | 位置（本机） | 说明 |
|---|---|---|
| Skill 本体 | `~/.kimi-code/skills/quarkclouddrive/` | SKILL.md + references/ + scripts/ |
| CLI 入口 | `~/.kimi-code/skills/quarkclouddrive/scripts/quark-drive.cjs` | Node ≥16 |
| 授权配置 | `~/.kimi-code/skills/quarkclouddrive/kimiwork/config.json` | 含 deviceId 和账号 token，**换渠道要重新授权** |
| 扫描产物 | `kimiwork/search/<userId>/*.jsonl` | browse/search 的 artifact 落盘 |

**在新 agent 上从零安装**：

```bash
# 1. 查服务端最新版（返回 JSON，取 data.config.qkPan 作为 zip 地址）
curl -fsSL "https://open-api-drive.quark.cn/agent/v1/skill_config?req_id=$(date +%s)"

# 2. 下载并解压到该 agent 的全局 skills 目录（不要装到项目级目录）
unzip quarkclouddrive-x.y.z.zip -d <agent全局skills目录>/quarkclouddrive

# 3. 自检（每次调用 CLI 前都应跑一次）
bash <agent全局skills目录>/quarkclouddrive/scripts/install.sh
```

## 3. ⚠️ 最大的坑：Agent 环境识别

CLI 每次运行都会识别宿主 agent 环境，**不认识就拒绝执行**：

```json
{"code":-104,"msg":"无法识别当前 Agent 环境，禁止继续使用"}
```

识别依据 = `process.cwd()` 路径 + 环境变量。已确认的支持矩阵：

| Agent | 通过条件 |
|---|---|
| Claude Code | 环境变量 `CLAUDECODE=1`（Claude Code 自动设置），原生支持 |
| OpenClaw | `OPENCLAW_CLI=1` 或 `OPENCLAW_SERVICE_MARKER=openclaw` |
| Qoder / Doubao / Codex / WorkBuddy 等 | 各有对应环境变量，见 CLI 的 `resolve-agent` 命令输出 |
| **Kimi Code** | **不在白名单**。Workaround：在路径含 `.kimi-work` 的目录下运行 CLI，会被识别为 `kimiwork` 渠道 |

Kimi Code 下的标准调用姿势（**所有命令都要这样跑**）：

```bash
cd ~/.kimi-work && node ~/.kimi-code/skills/quarkclouddrive/scripts/quark-drive.cjs <command> ...
```

**授权跟着渠道走**：config.json 存在 `<skills目录>/quarkclouddrive/<渠道名>/` 下。本机已完成的授权在 `kimiwork` 渠道——只要继续用上面的姿势调用就**免重新授权**；换成 claudecode 等其他渠道身份运行则需要重新 `login`。

验证环境识别是否通过：

```bash
cd ~/.kimi-work && node .../quark-drive.cjs resolve-agent
# 成功输出 QK_AGENT_ID=kimiwork；失败输出 code:-104
```

## 4. 授权

```bash
# 浏览器 OAuth，阻塞等待；授权码模式用 --token <code>
node .../quark-drive.cjs login

# 探活 / 查账号（昵称、会员、容量）
node .../quark-drive.cjs get-user-info
```

授权过期特征：stdout 的 NDJSON 中 `code` 为负数且 `msg` 含「未授权/认证/token」。此时不要重复原命令，重新 login。

**公共参数**（Skill 行为规范要求，服务质量追踪用，建议带上）：
- `--session-id "<unix秒>-<6位随机>"`：一个对话生成一次，全程复用
- `--session-input "<用户原始提问>"`：逐字复制，不改写

## 5. 脚本用法（本目录 scripts/）

前置环境变量（也可以直接改脚本顶部常量）：

```bash
export QUARK_CLI=~/.kimi-code/skills/quarkclouddrive/scripts/quark-drive.cjs
export QUARK_WORKDIR=~/.kimi-work        # 触发 kimiwork 识别的工作目录
export QUARK_SESSION_ID="$(date +%s)-$(head -c3 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

### 5.1 全量扫描 `scan.js`

```bash
node scan.js --out ./scan-out [--root-fid 0] [--max-depth 4]
```

- 从 `--root-fid`（默认 0 = 根目录）开始，逐层 `browse --all` 到 `--max-depth`
- 产出 `./scan-out/all-items.json`：`[{folder, fid, filename, size, type, updated}]`
- 参考耗时：5 万项 / 4 层 ≈ 25 分钟（服务端分页有节奏控制，别并发太猛）

### 5.2 查重 + 生成安全计划 `dedup.js`

```bash
node dedup.js --in ./scan-out/all-items.json --out ./dup-plan.json [--keep-pattern "^(?!我的备份)"]
```

- 按 `文件名|大小` 分组，组内 >1 即重复
- **安全保证：每组至少保留一份**。`--keep-pattern` 命中的副本优先保留（默认优先保留不在「我的备份」里的）
- 产出移动计划 + 可释放空间统计

### 5.3 执行移动计划 `run-move-plan.js`

```bash
# 先建隔离夹（在根目录下，fid 从返回里取）
node $QUARK_CLI create-folder --dir-path "_待清理" --parent-fid "0"

node run-move-plan.js --plan ./dup-plan.json --target-fid <隔离夹fid>
```

- 按目的地分批（≤50/批），批量失败自动降级逐个移动，最终输出成功/失败清单
- 同一隔离夹内同名文件由服务端自动重命名，不会互相覆盖

### 5.4 典型顺序

```bash
node scan.js --out ./out --max-depth 4
node dedup.js --in ./out/all-items.json --out ./dup-plan.json
# ← 把重复组清单展示给用户确认，这步不要省
node run-move-plan.js --plan ./dup-plan.json --target-fid <_待清理fid>
# ← 告知用户去 App 删除 _待清理
```

## 6. AI 相册整理（可选）

仅支持**图片/视频**，不支持文档；自包含（禁止先 search 再调用）：

```bash
node $QUARK_CLI organize --query "把2026年的照片按每次出游分类，同一次出游的风景和人像放一起"
```

- 涉及文件 >500 时返回 `code:-1609`，`msg` 是给用户看的方案预览（目录树），`data.task_id` 用于确认
- 用户选复制 → `organize-copy --task-id <id>`；选移动 → `organize-move --task-id <id>`
- 默认落点是 `夸克网盘/来自：<渠道名>/`（本机为「来自：KimiWork」）
- 结果里的 `check_all_link` 要原样给用户，`browse_hint` 文案禁止改写

## 7. 硬限制清单（别再踩）

1. **没有删除 API**。清理 = 移到 `_待清理` + 人工在 App 删除
2. `move` 单次最多 100 个 FID；批量调用只要一个 FID 失效就整批失败（报错「文件找不到」）→ 必须有逐个降级
3. `browse` 不递归、只列直接子项；`--all` 才出 artifact 落盘文件
4. `search` 一个任务只能调一次，无结果禁止换词重搜（Skill 行为规范）
5. `organize` 不支持「移动语义」的直接指令，必须走 confirm 流程；文档/压缩包整理会被拒
6. 目录参数（`--parent-fid` 等）用户没明说就不要自作主张填 `"0"`
7. Windows 下 Node 的 `require()` 不认 Git Bash 的 `/f/...` 路径，传 `F:/...`
8. `while read` 读没有末尾换行的文件会丢最后一行（本次踩过）

## 8. 卸载（不可逆，需用户二次确认）

```bash
bash ~/.kimi-code/skills/quarkclouddrive/scripts/uninstall.sh   # 撤销授权+清配置
rm -rf ~/.kimi-code/skills/quarkclouddrive                       # 删 skill 本体
```

## 9. 本次实战的关键数据（供参考）

- 规模：根 23 夹 → 4 层共 51,667 项 → 照片专项 4,743 张
- 重复：214 组、244 个多余副本、13.2GB（主因：三台设备相册备份 × 已整理照片夹）
- 空间大头：综艺视频 556GB、DeepSeek 模型权重 113GB(.gguf)
- 最终结构：影视综艺 / 学习资料 / 技术资料 / 照片相册 / 工作(古建课程·AI课程) / 个人事务 / 我的备份 / _待清理
