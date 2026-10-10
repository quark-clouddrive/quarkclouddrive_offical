# 文件操作

所有命令的 stdout 输出遵循 NDJSON 协议，每行一个 JSON 对象（统一为 `IApiType` 格式）。调试提示信息输出到 stderr（仅 `--verbose` 模式可见）；升级提示通过成功 `result` 的 `notice` 字段输出到 stdout。

> **notice.text 展示（强制）**：每次必须读取最终 `result.notice.text`；只要非空，无论命令成功或失败、`notice.kind` 为何值，都必须在业务结果或错误说明之后另起一段完整原样展示，不得省略、概括或改写。仅在工具输出中出现，不算已向用户展示。只展示实际返回的内容，不自行追加引导文案。详见 [SKILL.md](../SKILL.md) 的“notice.text 展示（强制）”。

> **升级提示展示**：本文件内所有命令及子命令成功时，若 `result.notice.kind` 为 `"skill_updated"`，先按原规则展示业务结果，再另起一段完整原样展示 `result.notice.text`。不展示字段名，不改写提示，也不将提示并入业务 `msg`。每次是否携带 `--skill-updated`，按 [SKILL.md](../SKILL.md) 中 `install.sh` 的实际返回结果判断。 升级提示和会员提示中的 URL 与搜索结果表格“查看链接”列采用相同展示规则：优先使用 Markdown 渲染为可点击的蓝链（升级提示使用 `[查看会员权益介绍](URL)`，普通会员提示使用 `[去升级](URL)`）；若当前环境不支持可点击链接，则直接展示完整原始 URL，方便用户复制访问。禁止将链接放入代码块或行内代码，禁止截断、改写 URL，或只展示无法点击且不含地址的“查看会员权益介绍”/“去升级”文字。此降级仅改变链接展示形式，提示文案和 URL 原值保持不变；未返回链接时仅展示原有文案，不自行补造地址。

## NDJSON 统一输出格式（IApiType）

所有 stdout 输出行均遵循以下结构：

```typescript
{
  code?: number;       // 状态码，0 为成功，负数为 CLI 错误码（progress 类型不含 code）
  msg: string;         // 状态描述
  action: string;      // 命令名称（如 "upload"、"download"）
  type: string; // 输出类型："result" | "progress" | "list" | "artifact"
  data: object;        // 业务数据
  notice?: { kind: "skill_updated" | "member_hint"; text: string }; // result 可携带的独立升级或会员提示
}
```

- **`type: "result"`** — 命令业务结果；不生成 Artifact 的命令以该行结束。Wild 升级后的成功结果可额外包含顶层 `notice: { kind: "skill_updated", text: string }`，由 Agent 在业务结果后原样独立展示；每次调用的传参判断规则见 [SKILL.md](../SKILL.md) 中执行 `scripts/install.sh` 的说明
- **`type: "progress"`** — 长任务（上传）的中间进度
- **`type: "list"`** — 列表条目（如 upload 的失败任务；browse 不使用此类型）
- **`type: "artifact"`** — 完整查询结果文件；Search 与 browse 成功时在 `result` 后输出，结构和消费规则见 [file-search.md](file-search.md)

**失败处理**：命令失败时通过 `CliExitError` 抛出（进程退出码 1），顶层 `quark-drive.ts` 的 catch 捕获后输出一行 `IApiType` 格式的错误结果到 stdout：

```jsonl
{"code":<错误码>,"msg":"<错误信息>","data":{},"action":"<命令名>","type":"result"}
```

- **`code`**：来自 `CliExitError.errorCode`，即 `error_constants.ts` 中定义的负数错误码
- **`msg`**：来自 `CliExitError.message`，为 `CLI_ERROR_MAP` 中的默认消息或命令中通过 `customMsg` 覆盖的动态消息
- **`data`**：固定为 `{}`
- **`action`**：来自 `CliExitError.action`，即命令名称
- **`type`**：固定为 `"result"`

---

## 目录 FID 说明

网盘中每个目录都有一个唯一的目录 FID（字符串类型）。特殊值 `"0"` 代表**根目录**（网盘最顶层目录）。

> **重要约束（面向 AI agent）**：`upload` 和 `saveas` 命令的目标目录参数（`--parent-fid`、`--to-pdir-fid`、`--to-pdir-path`）均为**选填参数**。当用户没有明确指定保存到哪个目录时，**严禁自行补充 `"0"` 或任何目录参数**，必须省略该参数，让 CLI 使用内部默认行为。只有当用户明确说"保存到根目录"或提供了具体的目录 FID/路径时，才传入对应参数。唯一例外是用户查看分享更新后只选择其中部分文件转存：必须按 `file-saveas.md` 的流程调用 `get-share-saved-dir`；成功返回 `data.pdir_fid` 时传给 `saveas --to-pdir-fid`，无返回或失败时省略目录参数直接调用 `saveas`。

---

## 整理任务与独立操作

文件夹/全盘归类移动先读 [文件整理](file-batch-organize.md)，在同一任务中通过 `file-organize` 执行和撤回。独立移动、创建目录、重命名仍按各自原有命令执行，不受整理流程替代。整理错误的 data 可包含上下文和 error，具体按该文档处理，不套用下方旧命令 data 为空的示例。

## 命令

> 批量重命名与整批撤销使用 `rename` / `rename-revert`，详见 [file-rename.md](file-rename.md)。

### 浏览文件夹直接子项（browse）

`browse` 调用 `file/list`，只列出指定文件夹的直接子项，不递归，也不支持关键词搜索。Search 与 Browse 的选择路由、共同 Artifact、FileVO 和聚合去重规则见 [file-search.md](file-search.md)。

未传 `--task-dir` 时，每次 browse（含不带 `--all`）都将 JSONL 写到 `<当前工作目录>/browse/browse-YYYYMMDD-HHMMSS-<6位随机十六进制>.jsonl`，与 Search 缓存分开。从用户工作目录调用 CLI 脚本的绝对路径，不要为运行 browse 而 cd 到 Skill 安装目录；读取返回的 file_path，不拼接文件名。空结果也落盘，失败不返回成功文件路径。

**使用边界**：`browse` 用于“列出目录内容”“看看目录下有哪些文件”等直接子项清单需求，以及基于该清单的筛选或后续批量操作。用户说“搜索 xx”“在 xx 目录搜索 yy”时优先使用 `search`；指定目录时传入 `--parent-fid`，目录 FID 未知时先用 `search --search-type dir --keyword "<目录名>" --stdout-only` 定位。不要因为提到目录、类型或后缀就先调用 `browse`，也不要用 `browse` 加本地文件名筛选替代搜索。

```bash
node scripts/quark-drive.cjs browse \
  [--parent-fid "<FOLDER_FID>"] \
  [--page-size <1-100>] \
  [--all] \
  [--task-dir "<TASK_DIR>"]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--parent-fid` | `0` | 目标文件夹 FID，`0` 表示根目录 |
| `--page-size` | `100` | 单页大小，范围 1～100 |
| `--all` | 关闭 | 自动获取全部直接子项 |
| `--task-dir` | 不传 | 整理任务目录；写入其 browse/ 子目录并在 result 返回文件路径 |

以下两种输出适用于**不传 --task-dir**：

- result.data.file_list 仅供预览，最多 5 条；本次完整数据读取 artifact.data.file_path。
- 不传 `--all` 时只查询一页：stdout 输出有界预览 `type:"result"` 和本页 JSONL `type:"artifact"`，不逐条输出 list；`result.data.total` 是本页条数，`result.data.hasMore` 表示是否还有下一页，Artifact 只含本页，hasMore=true 时不能视为全量。
- 传入 `--all` 时按 cursor 获取全部直接子项：stdout 输出有界预览 `result`（hasMore=false）和完整 JSONL `artifact`；Artifact 的结构与消费规则见 [file-search.md](file-search.md)。
- `--all` 分页遵循服务端 `metadata.tq_gap` 控制下一页请求间隔；缺失或无效时按 0ms。`file_list` 缺失或为 `null` 时按空数组处理，空页或只有重复项的页继续按分页状态处理；其他非数组值仍视为分页协议错误。cursor 循环、任一页请求失败或 Artifact 写入失败时命令整体失败，不发布本次 Artifact。

传 `--task-dir` 时，两种分页模式均只输出最终 result，data 为 `{file_path,parent_fid,count,hasMore}`，不再输出 list/artifact。每次查询生成独立的 `browse/browse-YYYYMMDD-HHMMSS-<6位随机十六进制>.jsonl`；读取返回路径，不自行拼文件名。失败不返回成功路径。不传 --all 仍只查询一页，hasMore=true 时不能声称全量；--all 不递归。

---

### 创建文件夹（create-folder）

在网盘指定目录下创建文件夹。同名文件夹重复创建时具有幂等性，返回已有文件夹的 FID。

#### 入参

```bash
node scripts/quark-drive.cjs create-folder --dir-path <DIR_PATH> [--parent-fid <PDIR_FID>]
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--dir-path <path>` | string | 必填 | — | 文件夹名称或路径 |
| `--parent-fid <fid>` | string | 选填 | 服务端默认目录 | 父目录 FID（`"0"` 代表根目录） |

> **重要（面向 AI agent）**：`--parent-fid` 不传时，服务端会将文件夹创建在平台默认目录中，**而非根目录**。当用户明确要求在根目录下创建文件夹时，**必须**传入 `--parent-fid "0"`；当用户指定了具体目录 FID 时，传入对应 FID。仅当用户未指定目录且无明确偏好时，才可省略该参数。

#### 成功出参

仅一行 `type: "result"`，无进度输出。

**result.data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `fid` | string | 创建的文件夹 FID |
| `full_path` | string | 文件夹完整路径（从「夸克网盘」根目录拼接，如 `"夸克网盘/我的备份/my-folder"`）。路径解析失败时不返回该字段 |

**成功示例**：

```jsonl
{"code":0,"msg":"成功","data":{"fid":"4cdd65bd1a2b3c4d","full_path":"夸克网盘/我的备份/my-folder"},"action":"create-folder","type":"result"}
```

#### 失败出参

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -601 | 缺少必要参数: --dir-path | 未传 `--dir-path` 参数 |
| -602 | 文件浏览器实例不存在 | SDK 文件浏览器初始化失败，`msg` 使用默认消息 |
| -603 | 创建操作失败 | SDK `createFolder` 返回 `status !== 0`，`msg` 优先使用 SDK 返回的 `error_info`，无则使用默认消息 |

**失败示例**：

```jsonl
{"code":-601,"msg":"缺少必要参数: --dir-path","data":{},"action":"create-folder","type":"result"}
```

```jsonl
{"code":-602,"msg":"文件浏览器实例不存在","data":{},"action":"create-folder","type":"result"}
```

```jsonl
{"code":-603,"msg":"parent folder not found","data":{},"action":"create-folder","type":"result"}
```

---

### 移动（move）

移动文件或文件夹到目标目录。支持同时移动多个文件（最多 100 个），使用同步移动模式（type=1）。

#### 入参

```bash
node scripts/quark-drive.cjs move <FID1> [FID2...] --target-fid <TARGET_FID>
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `[fids...]` | string[] | 必填 | — | 要移动的文件 FID 列表（位置参数，至少一个） |
| `--target-fid <fid>` | string | 必填 | — | 目标目录 FID |

#### 成功出参

仅一行 `type: "result"`，无进度输出。

**result.data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `fids` | string[] | 移动的文件 FID 列表 |
| `targetFid` | string | 实际移动到的目标目录 FID。通常等于入参 `--target-fid`；若服务端异步任务返回最终目录，则以服务端返回值为准 |
| `move_path` | string | 实际移动到的目标目录完整路径（含目标目录自身名称，如 `"夸克网盘/文档/目标文件夹"`）。路径解析失败时不返回该字段 |

**成功示例**：

```jsonl
{"code":0,"msg":"成功","data":{"fids":["e33ed06b1a2b3c4d","f44fe17c2b3c4d5e"],"targetFid":"4cdd65bd1a2b3c4d","move_path":"夸克网盘/文档/目标文件夹"},"action":"move","type":"result"}
```

#### 失败出参

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -501 | 缺少必要参数: 文件 FID 列表 | 未传入任何 FID 参数 |
| -502 | 缺少必要参数: --target-fid | 未传 `--target-fid` 参数 |
| -503 | 文件浏览器实例不存在 | SDK 文件浏览器初始化失败，`msg` 使用默认消息 |
| -504 | 移动操作失败 | SDK `moveFiles` 返回 `status !== 0`，`msg` 优先使用 SDK 返回的 `error_info`，无则使用默认消息 |

**失败示例**：

```jsonl
{"code":-501,"msg":"缺少必要参数: 文件 FID 列表","data":{},"action":"move","type":"result"}
```

```jsonl
{"code":-502,"msg":"缺少必要参数: --target-fid","data":{},"action":"move","type":"result"}
```

```jsonl
{"code":-503,"msg":"文件浏览器实例不存在","data":{},"action":"move","type":"result"}
```

```jsonl
{"code":-504,"msg":"target folder not found","data":{},"action":"move","type":"result"}
```

整理命令的会员提示统一使用顶层 `notice.text`（含可点击的会员链接），成功或服务端失败均可能返回；展示方式及升级提示优先覆盖规则见 [文件整理](file-organize.md#会员提示输出)。

文件总结和问答（`summary` / `qa`）的轮询超时阈值均为 5 分钟（300 秒），轮询间隔为 2 秒；会员提示同样复用顶层 `notice.text`，详见 [助手能力](assistant.md)。

`organize`、`organize-copy`、`organize-move`、`summary` 和 `qa` 涉及权益次数，相关提交、轮询、确认请求发生网络异常时 CLI 不自动重发，Agent 也不得自动重新执行命令；正常任务轮询不受影响。详见 [文件整理](file-organize.md) 和 [助手能力](assistant.md)。

轮询超时返回 `-1507`，`msg` 为：“这个问题涉及的文件比较多，处理超时了。你可以重新问一遍，或者告诉我文件大概在哪个文件夹，我缩小范围后能答得更快更准。”
