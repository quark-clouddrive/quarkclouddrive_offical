# 转存分享链接（saveas）

将分享链接中的文件转存到自己的网盘。默认转存整个分享链接，也可通过 `--fid-list` 指定部分文件。用户只需传入完整的分享链接 URL，CLI 内部自动解析 pwd_id、获取 stoken，并在使用 `--fid-list` 时自动匹配 `share_fid_token`。SDK 内部自动以 1 秒间隔轮询任务状态，不限轮询次数，仅受 15 分钟超时控制。单次查询失败时记录日志并继续重试，不中断轮询。任务完成（status=2）时输出成功结果，任务失败（status=3）时输出错误信息。

## Agent 命令选择

| 用户意图 | 调用命令 |
|------|------|
| 普通转存或保存分享链接，未提及“更新”“新增”“增量” | `saveas` |
| 分享链接从未转存，用户希望把链接内容存入网盘 | `saveas` |
| 转存分享链接中的全部新增或更新内容，例如“把这个链接的更新都存入网盘” | `saveas-update` |
| 查询指定分享链接是否有更新、更新了哪些文件，但没有要求转存 | `get-share-update-files` |
| 查看更新文件后，只转存其中明确选中的部分文件 | `get-share-saved-dir` → `saveas --fid-list ... --to-pdir-fid ...` |

`saveas-update` 只转存源分享中新增或更新的内容，不处理未变化的内容；它不是 `saveas` 的默认替代命令。该命令的前提是同一分享链接已经转存过：如果链接从未转存，系统没有历史转存记录和上次转存目录，无法检测或增量转存更新。此时用户希望转存链接内容，必须调用 `saveas` 完成首次转存，不能调用 `saveas-update`。

用户只说“转存这个分享”“保存这个链接”时必须调用 `saveas`。只有链接已经转存过，且用户明确要求转存全部“更新”“新增内容”时，才调用 `saveas-update`。如果用户只是查看链接是否有更新，应先使用 `get-share-update-files`；后续要求转存全部更新时使用 `saveas-update`，只选择部分更新文件时必须使用下面的历史转存目录流程。

## 查询历史转存目录（get-share-saved-dir）

根据分享链接的 `pwd_id` 调用 `getSaveAsDir`，获取该链接上次转存使用的目录。该命令不获取 stoken，也不接收提取码参数。

```bash
node scripts/quark-drive.cjs get-share-saved-dir --url <URL>
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--url <string>` | string | 必填 | — | 完整分享链接，命令从中解析 `pwd_id` |

成功时输出一行 `type: "result"`，`data` 透传 `getSaveAsDir` 返回的目录信息：

```jsonl
{"code":0,"msg":"成功","data":{"pdir_fid":"dir123","pdir_name":"分享标题","old_pdir_name":"旧目录名","strategy":"..."},"action":"get-share-saved-dir","type":"result"}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `pdir_fid` | string | 历史转存目标目录 FID |
| `pdir_name` | string | 当前目标目录名称 |
| `old_pdir_name` | string | 旧目标目录名称 |
| `strategy` | string | 服务端选定目录的策略 |

> **更新文件部分转存目录约束（必须遵守）**：用户明确先查看有更新的文件，随后只要求转存其中部分文件时，禁止调用会转存全部新增内容的 `saveas-update`。必须先执行 `get-share-saved-dir --url <URL>`：成功且 `data.pdir_fid` 非空时，执行 `saveas --url <URL> --fid-list <用户选中的更新文件FID> --to-pdir-fid <pdir_fid>`；如果没有返回结果、未返回有效 `pdir_fid` 或命令执行出错，不得阻断转存，直接执行 `saveas --url <URL> --fid-list <用户选中的更新文件FID>`，省略目录参数并使用 CLI 默认转存位置。成功返回的目录 FID 是目录参数禁止自动填充规则的明确例外；降级时禁止自行补充 `"0"` 或其他目录值。两个命令都必须携带 Wild 模式要求的公共参数。

```bash
# 用户查看更新文件后，只选择 file1 和 file2 存入上次转存目录
node scripts/quark-drive.cjs get-share-saved-dir --url "https://pan.quark.cn/s/abc123" --session-input "用户原始提问" --session-id "1784035443-a1b2c3"
node scripts/quark-drive.cjs saveas --url "https://pan.quark.cn/s/abc123" --fid-list file1,file2 --to-pdir-fid dir123 --session-input "用户原始提问" --session-id "1784035443-a1b2c3"

# get-share-saved-dir 无返回或失败：不指定目录，仍继续转存选中文件
node scripts/quark-drive.cjs saveas --url "https://pan.quark.cn/s/abc123" --fid-list file1,file2 --session-input "用户原始提问" --session-id "1784035443-a1b2c3"
```

失败时使用以下本地错误码兜底；接口返回有效 `errno` 或错误信息时优先透传：

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -2101 | 无效的分享链接 URL | `--url` 为空或格式无效 |
| -2102 | 初始化历史转存目录查询失败 | SDK 或分享管理器初始化异常 |
| -2103 | 请求历史转存目录失败 | `getSaveAsDir` 调用抛出异常 |
| -2104 | 历史转存目录响应格式异常 | 成功响应未返回有效 `pdir_fid` |
| -2105 | 获取历史转存目录失败 | 接口返回失败状态 |

## 转存分享链接中的更新（saveas-update）

当用户要把已转存分享中的新增文件继续存入网盘时，使用独立命令：

```bash
node scripts/quark-drive.cjs saveas-update --url <URL>
```

该命令不接收提取码参数，先调用 `getShareDetail` 获取 stoken；仅当分享详情没有返回有效 stoken 时，才按链接中的 `pwd_id` 调用 `/open/v1/share/saved/stoken` 兜底获取。取得令牌后，命令会自动找到上次转存目录并仅转存新增内容。禁止为它补充目录或文件列表参数。

**首次转存与增量转存示例**

```bash
# 链接从未转存：无法检测更新，首次保存必须使用 saveas
node scripts/quark-drive.cjs saveas --url "https://pan.quark.cn/s/abc123"

# 同一链接已经转存过，用户随后要求只保存新增内容：使用 saveas-update
node scripts/quark-drive.cjs saveas-update --url "https://pan.quark.cn/s/abc123"

```

例如，用户说“这个链接还没存过，帮我转存到网盘”，应调用 `saveas`；用户说“这个链接之前存过，帮我把后来新增的内容也存下来”，才调用 `saveas-update`。

成功输出示例：

```jsonl
{"code":0,"msg":"已将新增文件存入「夸克网盘/来自：分享/分享标题」","data":{"task_id":"task123","task_type":17,"status":2,"pwd_id":"abc123","save_path":"夸克网盘/来自：分享/分享标题"},"action":"saveas-update","type":"result"}
```

> **结果展示硬约束（必须遵守）**：`saveas-update` 成功后，必须将返回结果的 `msg` 字段完整、原样地作为最终回复直接展示给用户。禁止根据 `data`、保存路径或其他字段重新组织文案；禁止对 `msg` 进行概括、扩写、同义改写，或添加任何前后缀。

> **再次转存确认约束（必须遵守）**：`saveas-update` 返回成功即表示本次检测到的新增文件已经存入网盘，不是待执行或待确认状态。成功后禁止 agent 自动重试或再次调用该命令。如果用户希望再次转存，必须先调用 `get-share-update-files --url <URL>` 重新查询该链接是否有更新；查询成功且存在更新文件时，先展示更新文件表格，再完整原样展示 `msg`，由 `msg` 自带的询问完成确认，禁止另行改写或追加询问。用户明确同意后才能再次调用 `saveas-update`；如果没有更新，只原样展示查询结果的 `msg`，不得调用 `saveas-update`。该约束不得破坏上述成功 `msg` 原样输出规则：本次成功回复仍只展示 `msg`，查询与确认发生在后续再次转存之前。

失败时使用以下本地错误码作为兜底；接口返回有效 `errno` 或 `error_info` 时，最终 `code` 和 `msg` 优先透传服务端值。

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -1201 | 分享管理器实例不存在 | 初始化完成后未取得分享管理器 |
| -1202 | 增量转存操作失败 | 兼容保留，当前流程不再用作多个阶段的通用错误 |
| -1203 | 无效的分享链接 URL | `--url` 不是合法的夸克网盘分享链接 |
| -1204 | 获取分享令牌失败 | 分享详情未返回 stoken，且通过 `/open/v1/share/saved/stoken` 兜底获取也失败 |
| -1205 | SDK 初始化失败 | 初始化 SDK 时发生异常 |
| -1206 | 分享管理器初始化失败 | 登录态分享管理器初始化失败 |
| -1207 | 获取上次转存目录失败 | `getSaveAsDir` 请求失败或未返回 `pdir_fid` |
| -1208 | 提交增量转存任务失败 | `saveAs` 的 `mode=inc` 请求失败或未返回任务 ID |
| -1209 | 增量转存任务轮询超时 | 15 分钟内未取得终态 |
| -1210 | 查询增量转存任务失败 | 轮询接口连续失败或未返回任务数据 |
| -1211 | 增量转存任务失败 | 任务终态为失败 |
| -1212 | 增量转存任务已暂停 | 任务终态为暂停 |
| 41043 | 链接未转存 | 服务端未找到历史转存记录，无法检测或增量转存更新 |

收到 `41043` 后，如果用户只想查询更新，应告知该链接尚未转存、当前无法检测更新；如果用户希望把链接内容转存到网盘，应改用普通 `saveas`，不要重试 `saveas-update`。

```jsonl
{"code":-1203,"msg":"无效的分享链接 URL","data":{},"action":"saveas-update","type":"result"}
```

## 入参

```bash
node scripts/quark-drive.cjs saveas --url <URL> [--fid-list <FIDS>] [--to-pdir-path <PATH>] [--passcode <CODE>]
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--url <string>` | string | 必填 | — | 分享链接 URL（如 `https://pan.quark.cn/s/xxx` 或带提取码 `https://pan.quark.cn/s/xxx?pwd=abcd`） |
| `--save-all` | boolean | 选填 | `true` | 转存整个分享链接（默认行为，与 `--fid-list` 互斥） |
| `--fid-list <string>` | string | 选填 | — | 指定文件 FID 列表，逗号分隔（与 `--save-all` 互斥，CLI 内部自动匹配 `share_fid_token`） |
| `--to-pdir-path <string>` | string | 选填 | — | 保存目录路径。不传时由 CLI 内部决定默认行为 |
| `--to-pdir-fid <string>` | string | 选填 | — | 保存目录 FID（高级选项，推荐使用 `--to-pdir-path`）。不传时由 CLI 内部决定默认行为 |
| `--passcode <string>` | string | 选填 | — | 提取码。私密分享链接需要提供。如果 URL 中已带 `?pwd=abcd`，可不传此参数（CLI 会自动解析 URL 中的提取码）；如果同时提供了 `--passcode` 和 URL 中的 `pwd` 参数，以 `--passcode` 为准 |

> **重要（面向 AI agent）**：`--to-pdir-path` 和 `--to-pdir-fid` 均为选填参数。当用户没有明确指定转存到哪个目录时，**严禁自行补充 `"0"`、`"根目录"` 或任何值**，必须省略这些参数。只有当用户明确说"保存到根目录"或提供了具体的目录 FID/路径时，才传入对应参数。`"0"` 代表根目录。
>
> **指定目录的处理流程**：当用户指定了转存目标目录（如"保存到 XX 文件夹"）时，agent **必须**按以下步骤执行：
> 1. 先阅读搜索命令文档（[references/file-search.md](references/file-search.md)），调用 `search` 命令搜索该目录
> 2. 从搜索结果中找到目标目录的 `fid`
> 3. 将该 `fid` 作为 `--to-pdir-fid` 参数传入 `saveas` 命令
> 4. 如果搜索不到该目录，则**不传** `--to-pdir-fid` 和 `--to-pdir-path`，走 CLI 内部默认逻辑，并告知用户未找到指定目录、文件已转存到默认位置

**示例**

```bash
# 最简用法：转存整个分享链接（默认行为，无需指定目录参数）
node scripts/quark-drive.cjs saveas --url "https://pan.quark.cn/s/abc123"

# 转存到指定路径
node scripts/quark-drive.cjs saveas --url "https://pan.quark.cn/s/abc123" --to-pdir-path "/我的文件/下载"

# 转存指定文件（不指定目录）
node scripts/quark-drive.cjs saveas --url "https://pan.quark.cn/s/abc123" --fid-list fid1,fid2

# 带提取码的私密分享链接（提取码在 URL 中）
node scripts/quark-drive.cjs saveas --url "https://pan.quark.cn/s/abc123?pwd=abcd"

# 带提取码的私密分享链接（通过 --passcode 参数传入）
node scripts/quark-drive.cjs saveas --url "https://pan.quark.cn/s/abc123" --passcode "abcd"

# 显式使用 --save-all（效果等同于不传）
node scripts/quark-drive.cjs saveas --url "https://pan.quark.cn/s/abc123" --save-all
```

## 成功出参

输出 NDJSON，仅一行 `type: "result"`，无进度输出。`code` 为 `0` 表示转存成功：

```jsonl
{"code":0,"msg":"成功","data":{"task_id":"xxx","task_type":17,"status":2,"save_as":{"to_pdir_fid":"0","to_pdir_name":"根目录"},"save_path":"网盘根目录"},"action":"saveas","type":"result"}
```

> **agent 须知**：
> - `code` 为 `0` 时表示转存成功，此时 `data` 中包含任务详情和保存目录信息
> - `code` 不为 `0` 时表示转存未成功，agent **必须**将 `msg` 字段的内容告知用户，并终止后续任务，禁止忽略错误继续执行

**result 行 data 字段**（成功时）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `task_id` | string | 异步任务 ID |
| `task_type` | number | 任务类型（17=转存） |
| `status` | number | 任务状态（成功时为 2） |
| `save_as.to_pdir_fid` | string | 保存目标目录 FID |
| `save_as.to_pdir_name` | string | 保存目标目录名称 |
| `save_path` | string | 保存目标目录的完整路径（含目录自身名称，以 `"夸克网盘/"` 为前缀，如 `"夸克网盘/我的文件/下载"`；根目录时为 `"网盘根目录"`）。路径解析失败时不返回该字段 |

**任务状态码**：

| 状态码 | 含义 |
|--------|------|
| 0 | 待处理 |
| 1 | 处理中 |
| 2 | 完成 |
| 3 | 失败 |
| 4 | 暂停 |

**转存成功时的人类可读输出**：

转存成功时，CLI 会通过 stderr 输出人类可读的提示信息（仅 `--verbose` 模式可见），告知用户转存结果和目标目录：

```
✔ 转存完成！
保存目录 FID: <to_pdir_fid>
保存目录名称: <to_pdir_name>
```

在转存成功后，应使用 result 行中的 `save_as.to_pdir_name` 字段，告知用户转存结果，例如：

> 转存成功！文件已保存到「根目录」。

## 失败出参

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -1101 | --fid-list 和 --save-all 互斥 | 同时提供了 `--fid-list` 和 `--save-all` |
| -1104 | 分享管理器实例不存在 | SDK 分享管理器初始化失败 |
| -1105 | 转存操作失败 | SDK `saveAsWithTrace` 返回 `status !== 0` 且 errno 不匹配 -1107 的兜底错误（如 saveAs 接口失败、任务轮询超时、指定的 fid 无效等） |
| -1106 | 无效的分享链接 URL | `--url` 参数不是合法的夸克网盘分享链接 |
| -1107 | 获取分享令牌失败 | SDK 内部调用 `getShareDetail` 获取 stoken 失败（SDK errno=-1107） |
| -1108 | （已废弃）指定的 fid 在分享详情中找不到对应的 share_fid_token | SDK 现在采用尽力匹配模式，找不到 fid_token 的 fid 会被跳过并直接请求服务端，不再在客户端报错 |
| 32003 | 网盘空间已满 | 用户网盘存储空间不足，无法转存。服务端透传错误码，需提示用户清理空间或升级容量 |
| 32004 | 网盘空间已满 | 同 32003，用户网盘存储空间不足。服务端透传错误码，需提示用户清理空间或升级容量 |

> **agent 须知**：当 `code` 为 `32003` 或 `32004` 时，表示用户网盘空间已满，agent 应明确告知用户"网盘空间不足，请清理空间或升级容量后重试"，**不要重试转存操作**。
