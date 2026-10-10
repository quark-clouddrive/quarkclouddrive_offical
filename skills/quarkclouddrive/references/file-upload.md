# 上传（upload）

> **升级提示展示**：本文件内所有命令及子命令成功时，若 `result.notice.kind` 为 `"skill_updated"`，先按原规则展示业务结果，再另起一段完整原样展示 `result.notice.text`。不展示字段名，不改写提示，也不将提示并入业务 `msg`。每次是否携带 `--skill-updated`，按 [SKILL.md](../SKILL.md) 中 `install.sh` 的实际返回结果判断。 升级提示和会员提示中的 URL 与搜索结果表格“查看链接”列采用相同展示规则：优先使用 Markdown 渲染为可点击的蓝链（升级提示使用 `[查看会员权益介绍](URL)`，普通会员提示使用 `[去升级](URL)`）；若当前环境不支持可点击链接，则直接展示完整原始 URL，方便用户复制访问。禁止将链接放入代码块或行内代码，禁止截断、改写 URL，或只展示无法点击且不含地址的“查看会员权益介绍”/“去升级”文字。此降级仅改变链接展示形式，提示文案和 URL 原值保持不变；未返回链接时仅展示原有文案，不自行补造地址。

**会员提示展示（upload / upload resume）**：最终 `result.notice.kind` 为 `"member_hint"` 且 `notice.text` 非空时，先展示业务结果或错误，再另起一段原样展示该文本，保留可点击的 `[去升级](URL)`。不展示字段名，不将提示拼入 `msg`，不根据错误码或容量值自行生成会员话术。`list`、`progress` 不重复展示最终提醒；`notice.text` 为空或未返回 notice 时，不补造文案或地址。

多文件上传使用本次命令最后收到的文件终态服务端响应，文案与链接来自同一份响应。最后响应缺字段时不回填此前提示；本地文件错误、取消和网络异常没有服务端快照，不覆盖已有服务端快照。任一文件失败仍按失败展示，同时保留已成功文件明细，不自动重新上传整批文件。`32003` 表示主盘空间不足，`32004` 表示单文件大小超限；成功后的容量预警不改变上传成功状态。

成功结果满足升级提示条件时，只展示最终 `skill_updated` notice；失败不追加升级提示。续传只使用本次响应，不沿用历史任务提示。

上传文件或文件夹到网盘指定目录。支持同时传入多个路径，每个路径可以是文件或文件夹，SDK 自动递归上传文件夹内容。

## 入参

```bash
node scripts/quark-drive.cjs upload <PATH1> [PATH2] [PATH3...] [--parent-fid <PDIR_FID>]
node scripts/quark-drive.cjs upload --file-path <LOCAL_PATH> [--parent-fid <PDIR_FID>]
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `[paths...]` | string[] | 与 `--file-path` 二选一 | — | 本地文件或文件夹路径列表（variadic argument，支持多个） |
| `--file-path <path>` | string | 与 `paths` 二选一 | — | 本地文件或文件夹路径（向后兼容，推荐直接传参） |
| `--parent-fid <fid>` | string | 选填 | — | 目标目录 FID。不传时由 CLI 内部决定默认行为 |

> **重要（面向 AI agent）**：`--parent-fid` 是选填参数。当用户没有明确指定上传到哪个目录时，**严禁自行补充 `"0"` 或任何值**，必须省略该参数。只有当用户明确说"上传到根目录"或提供了具体的目录 FID 时，才传入该参数。`"0"` 代表根目录。

> **多文件上传（面向 AI agent）**：本 CLI 上传命令支持多路径上传，有两种方式：
> 1. **直接传入多个路径**（推荐）：`upload path1 path2 path3`，CLI 会逐个路径调用 SDK 上传，每个路径如果是文件夹则递归上传目录结构。
> 2. **传入文件夹路径**：将文件放入同一目录，传入目录路径即可一次性上传。
>
> 两种方式均支持混合使用（`upload ./file1.txt ./dir1 --file-path ./file2.txt`）。`paths` 参数和 `--file-path` 选项会合并去重。

## 成功出参

上传过程中持续输出 `type: "progress"` 进度行（`data.current`/`data.total` 为所有子任务的汇总字节数）。每个子任务到达终态时输出 `type: "list"` 行（成功或失败各一行）。最后一行为 `type: "result"`。

**progress 行 data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `current` | number | 已上传字节数（所有子任务汇总） |
| `total` | number | 总字节数（所有子任务汇总） |
| `percent` | number | 上传百分比（0-100 整数） |

**成功任务 list 行**（`code: 0`，单个子任务上传成功时输出）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.recordId` | string | 任务记录 ID |
| `data.fileId` | string | 上传成功的文件 FID |
| `data.fileName` | string | 文件名 |
| `data.fileSize` | number | 文件大小（字节） |
| `data.instantUpload` | boolean | 是否秒传（服务端已存在相同文件，跳过实际上传） |

**失败任务 list 行**（`code: SDK 错误码`，单个子任务上传失败时输出）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.recordId` | string | 失败任务的记录 ID |

**result 行**：所有子任务完成后输出。如果全部成功，`code: 0`；如果存在失败任务，优先透传服务端错误码，缺失时使用 `-204`。失败 result 的 `data.fids`、`data.successCount` 和 `data.failedCount` 保留已成功文件及失败数量。

**全部成功时 result 行 data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.fileNames` | string[] | 上传的文件/目录名列表 |
| `data.fileCount` | number | 传入的路径数量 |
| `data.totalSize` | number | 所有文件总大小（字节，文件夹不计入） |
| `data.fids` | string[] | 上传成功的文件 FID 列表 |
| `data.successCount` | number | 上传成功的任务数量 |
| `data.instantUpload` | boolean | 是否存在秒传文件（任一文件秒传即为 true） |
| `data.instantUploadCount` | number | 秒传成功的文件数量 |
| `data.fullPath` | string | 上传文件在网盘中的完整路径（以 `"夸克网盘/"` 为前缀，由第一个成功文件的 file/info 接口获取，尽力而为，失败时为空字符串）。路径不含文件自身名称，表示文件所在目录的完整路径 |

> **fullPath 解析规则（面向 AI agent）**：
> - `fullPath` 含 `/` 且非仅为前缀 → 向用户说"已上传到「{fullPath}」目录"
> - `fullPath` 为空字符串 `""` 或不含 `/` → 仅说"已上传到夸克网盘"，**绝对禁止说"根目录"**
> - 仅当用户明确请求"上传到根目录"且 Agent 显式传入了 `--parent-fid=0` 时，才能在回复中说"根目录"
> - ❌ 反例：`fullPath` 为 `"夸克网盘"`（不含 `/`）时说"已保存到根目录" — 这是错误的

**成功示例**（全部子任务成功）：

```jsonl
{"msg":"进行中","data":{"current":1048576,"total":10485760,"percent":10},"action":"upload","type":"progress"}
{"msg":"进行中","data":{"current":5242880,"total":10485760,"percent":50},"action":"upload","type":"progress"}
{"code":0,"msg":"上传成功","data":{"recordId":"rec_1","fileId":"844db92f066f4537b59ff668d1d75144","fileName":"test.txt","fileSize":256,"instantUpload":false},"action":"upload","type":"list"}
{"msg":"进行中","data":{"current":10485760,"total":10485760,"percent":100},"action":"upload","type":"progress"}
{"code":0,"msg":"成功","data":{"fileNames":["test.txt"],"fileCount":1,"totalSize":256,"fids":["844db92f066f4537b59ff668d1d75144"],"successCount":1,"instantUpload":false,"instantUploadCount":0,"fullPath":"夸克网盘/我的文档"},"action":"upload","type":"result"}
```

**部分失败示例**（保留已成功文件，最终 result 透传服务端错误码及当前提示）：

```jsonl
{"code":0,"msg":"上传成功","data":{"recordId":"rec_1","fileId":"file_1","fileName":"a.txt","fileSize":1024,"instantUpload":true},"action":"upload","type":"list"}
{"code":31003,"msg":"file hash conflict","data":{"recordId":"rec_abc123"},"action":"upload","type":"list"}
{"code":31003,"msg":"file hash conflict","data":{"fids":["file_1"],"successCount":1,"failedCount":1},"action":"upload","type":"result"}
```

## 失败出参

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -201 | 缺少必要参数: --file-path | 未传文件路径（`paths` 和 `--file-path` 均为空） |
| -202 | 文件不存在 | 指定的本地文件路径不存在，错误信息会附带具体路径 |
| -203 | 上传管理器实例不存在 | SDK 上传管理器初始化失败，`msg` 使用默认消息 |
| -204 | 上传操作失败 | 所有上传任务完成后存在失败任务，`msg` 附带失败任务数量（如 `"上传操作失败, 失败任务数量: 2"`） |

**失败示例**：

```jsonl
{"code":-201,"msg":"缺少必要参数: --file-path","data":{},"action":"upload","type":"result"}
```

```jsonl
{"code":-202,"msg":"文件不存在: /path/to/nonexistent.txt","data":{},"action":"upload","type":"result"}
```

```jsonl
{"code":-203,"msg":"上传管理器实例不存在","data":{},"action":"upload","type":"result"}
```

```jsonl
{"code":-204,"msg":"上传操作失败, 失败任务数量: 2","data":{},"action":"upload","type":"result"}
```

## 断点续传子命令

上传支持断点续传。上传过程中按 Ctrl+C 会自动保存断点，后续可通过子命令管理和恢复任务。

### 列出上传任务（upload list）

列出所有持久化的上传任务记录。

```bash
node scripts/quark-drive.cjs upload list [--state <STATE>]
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--state <state>` | string | 选填 | — | 按状态过滤：`pending`/`hashing`/`uploading`/`paused`/`success`/`failed`/`cancelled`/`post_hashing` |

**成功出参**

逐条输出 `type: "list"` 行，最后一行为 `type: "result"`。

**list 行 data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `recordId` | string | 任务 ID |
| `fileName` | string | 文件名 |
| `fileSize` | number | 文件大小（字节） |
| `state` | string | 任务状态（`pending`/`hashing`/`uploading`/`paused`/`success`/`failed`/`cancelled`/`post_hashing`） |
| `createdAt` | number | 创建时间（毫秒时间戳） |

**成功示例**：

```jsonl
{"code":0,"msg":"","data":{"recordId":"abc123","fileName":"video.mp4","fileSize":104857600,"state":"paused","createdAt":1700000000000},"action":"upload-list","type":"list"}
{"code":0,"msg":"成功","data":{"totalCount":1},"action":"upload-list","type":"result"}
```

**失败出参**

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -209 | 加载持久化任务失败 | SDK `loadPersistedTasks` 返回 `status !== 0`，`msg` 附带 SDK 返回的 `error_info` |

### 恢复上传任务（upload resume）

从持久化存储恢复指定的上传任务并继续上传。恢复过程中按 Ctrl+C 同样会自动保存断点。

```bash
node scripts/quark-drive.cjs upload resume --record-id <ID>
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--record-id <id>` | string | 必填 | — | 任务 ID（从 `upload list` 获取） |

**成功出参**

上传过程中输出 `type: "progress"` 进度行，每个任务完成时输出 `type: "list"` 行，最后一行为 `type: "result"`。

**list 行 data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `recordId` | string | 任务 ID |
| `fileId` | string | 上传成功后的文件 FID |
| `fileName` | string | 文件名 |
| `fileSize` | number | 文件大小（字节） |
| `instantUpload` | boolean | 是否秒传 |

**成功示例**：

```jsonl
{"msg":"进行中","data":{"current":52428800,"total":104857600,"percent":50},"action":"upload-resume","type":"progress"}
{"code":0,"msg":"上传成功","data":{"recordId":"abc123","fileId":"fid456","fileName":"video.mp4","fileSize":104857600,"instantUpload":false},"action":"upload-resume","type":"list"}
{"code":0,"msg":"成功","data":{"recordId":"abc123","fileName":"video.mp4"},"action":"upload-resume","type":"result"}
```

**失败出参**

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -204 | 上传操作失败 | 上传任务 `onFailure` 回调触发，`code` 优先使用 SDK 返回的 `errorCode`，`msg` 优先使用 SDK 返回的 `errorMessage` |
| -205 | 任务不存在 | 指定的 `--record-id` 在持久化任务列表中不存在 |
| -208 | 恢复任务失败 | SDK `restoreTask` 返回失败，`msg` 附带具体错误信息 |
| -210 | 缺少必要参数: --record-id | 未传 `--record-id` 参数 |

**失败示例**：

```jsonl
{"code":-210,"msg":"缺少必要参数: --record-id","data":{},"action":"upload-resume","type":"result"}
```

```jsonl
{"code":-205,"msg":"未找到任务: abc123","data":{},"action":"upload-resume","type":"result"}
```

```jsonl
{"code":-208,"msg":"恢复失败: task expired","data":{},"action":"upload-resume","type":"result"}
```

### 删除上传任务记录（upload delete）

删除持久化的上传任务记录。

```bash
node scripts/quark-drive.cjs upload delete --record-id <ID>
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--record-id <id>` | string | 必填 | — | 任务 ID（从 `upload list` 获取） |

**成功出参**

仅一行 `type: "result"`，无进度输出。

**result.data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `recordId` | string | 已删除的任务 ID |

**成功示例**：

```jsonl
{"code":0,"msg":"成功","data":{"recordId":"abc123"},"action":"upload-delete","type":"result"}
```

**失败出参**

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -205 | 任务不存在 | 指定的 `--record-id` 在持久化任务列表中不存在 |
| -210 | 缺少必要参数: --record-id | 未传 `--record-id` 参数 |

**失败示例**：

```jsonl
{"code":-210,"msg":"缺少必要参数: --record-id","data":{},"action":"upload-delete","type":"result"}
```

```jsonl
{"code":-205,"msg":"未找到任务: abc123","data":{},"action":"upload-delete","type":"result"}
```

### 上传会员提示

`upload` 与 `upload resume` 将上传接口返回的 `member_hint`、`metadata.skill_vip_url` 转换为最终 `result.notice.text`，覆盖预上传秒传、update_hash 秒传、普通上传完成及服务端失败。文案与链接取自同一份文件终态响应。批量上传按本次最后收到的终态服务端响应选择提示，不受持久化回调顺序影响；最后响应缺少会员字段时不回填旧提示。业务失败与提示选择独立汇总，并保留已成功文件。

业务 `data` 和逐文件 `list` 不重复输出会员字段或 metadata。缺少文案和链接不生成会员 notice，明确空文案保留空字符串；Wild 成功升级提示优先覆盖会员 notice，失败不追加升级提示。Wild 下 Agent 在业务结果或错误说明后另起一段原样展示非空 `notice.text`，保留可点击的 `[去升级](URL)` 链接；环境不支持时展示完整原始 URL。
