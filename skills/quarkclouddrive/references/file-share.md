# 文件分享

分享相关命令：创建分享链接、获取分享详情、分享内搜索。

---

## 命令

### 分享（share）

创建分享链接，支持多个 FID 同时分享，支持公开/私密链接和过期时间设置。

#### 入参

```bash
node scripts/quark-drive.cjs share <FID1> [FID2...] [--title <TITLE>] [--url-type <NUMBER>] [--expired-type <NUMBER>]
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `[fids...]` | string[] | 必填 | — | 要分享的文件 FID 列表（位置参数） |
| `--title <string>` | string | 选填 | — | 分享标题 |
| `--url-type <number>` | number | 选填 | `1` | 链接类型：`1`=公开链接，`2`=私密链接（提取码由服务端自动生成） |
| `--expired-type <number>` | number | 选填 | `1` | 过期类型：`1`=永久有效，`2`=1天，`3`=7天，`4`=30天，`5`=60天，`6`=100天，`7`=180天 |

#### 成功出参

仅一行 `type: "result"`，无进度输出。`data` 透传 SDK 返回的分享信息。

**result.data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `share_url` | string | 分享链接 URL |
| `passcode` | string | 提取码（仅 `url-type=2` 私密链接时返回，由服务端自动生成） |

> 注意：私密链接的提取码不由调用方指定，而是由服务端自动生成后通过 `data.passcode` 字段返回。Agent 需要从返回结果中读取 `passcode` 才能拼出完整的分享信息给用户。

**成功示例（公开链接）**：

```jsonl
{"code":0,"msg":"成功","data":{"share_url":"https://pan.quark.cn/s/abc123def456"},"action":"share","type":"result"}
```

**成功示例（私密链接）**：

```jsonl
{"code":0,"msg":"成功","data":{"share_url":"https://pan.quark.cn/s/abc123def456","passcode":"xK9m"},"action":"share","type":"result"}
```

> **❗ 分享地址展示规则（wild 模式必做）**：
> - **优先**：把 `data.share_url` 渲染成**可点击跳转**的链接展示给用户（Markdown `[分享链接](share_url)`，确保终端/客户端可识别并点击跳转）。
> - **兜底**：当环境不支持可点击链接渲染时，**直接展示完整分享地址原文**（明文 URL），保证用户能复制访问。
> - 无论哪种方式都**禁止**用代码块 / 行内代码包裹或截断分享地址，导致无法点击或复制。
> - 私密链接（`url-type=2`）还需从 `data.passcode` 读取提取码并一并告知用户，拼成完整分享信息（如「链接：<可点击 URL 或明文 URL>　提取码：xK9m」）。

#### 失败出参

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -401 | 未提供文件 FID 列表 | 未传入任何 FID 参数 |
| -402 | 分享管理器实例不存在 | SDK 分享管理器初始化失败，`msg` 使用默认消息 |
| -403 | 分享操作失败 | SDK `share` 返回 `status !== 0`，`msg` 优先使用 SDK 返回的 `error_info`，无则为 `"未知错误"` |
| -404 | 无效的链接类型 | `--url-type` 值不是 `1` 或 `2`，`msg` 附带具体的无效值 |
| -405 | 无效的过期类型 | `--expired-type` 值不在 `1-7` 范围内，`msg` 附带具体的无效值 |

**失败示例**：

```jsonl
{"code":-401,"msg":"未提供文件 FID 列表","data":{},"action":"share","type":"result"}
```

```jsonl
{"code":-402,"msg":"分享管理器实例不存在","data":{},"action":"share","type":"result"}
```

```jsonl
{"code":-403,"msg":"invalid fid","data":{},"action":"share","type":"result"}
```

```jsonl
{"code":-404,"msg":"无效的链接类型: 3，仅支持 1(公开) 或 2(私密)","data":{},"action":"share","type":"result"}
```

```jsonl
{"code":-405,"msg":"无效的过期类型: 9，仅支持 1-7","data":{},"action":"share","type":"result"}
```

---

### 获取有更新的转存分享列表（get-share-update-list）

获取用户曾经转存、且源分享内容后来发生更新的链接列表。

#### Agent 调用流程

1. 用户未提供具体分享链接，而是询问“哪些已转存分享有更新”时，先调用本命令获取候选分享链接；如果用户已经提供具体链接，则直接调用 `get-share-update-files`。
2. 分享信息逐条出现在 `type: "list"` 行中，必须读取全部 `list` 行；最后的 `type: "result"` 只提供分页元数据。
3. 确定用户要查看的目标链接后，再调用 `get-share-update-files`。命令不接收提取码参数，会先请求分享详情，详情无 stoken 时再回退已转存令牌接口。
4. 不要默认对当前页每个分享链接逐一查询文件；目标不明确时先向用户展示候选分享并确认。

#### 入参

```bash
node scripts/quark-drive.cjs get-share-update-list [--page <NUMBER>] [--size <NUMBER>]
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--page <number>` | number | 选填 | `1` | 页码，从 1 开始；Agent 展示更新摘要时不传该参数，固定查询第 1 页 |
| `--size <number>` | number | 选填 | `50` | 每页条目数，范围 `1-50` |

#### 成功出参

每个有更新的分享链接输出一行 `type: "list"`，最后再输出一行 `type: "result"`。Agent 必须读取所有 `list` 行获取链接信息；最后的 `result.data` 提供总数、当前页和是否还有下一页。

**list.data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `pwd_id` | string | 分享链接唯一 ID |
| `share_url` | string | 完整分享链接 |
| `title` | string | 分享标题 |
| `updated_at` | string | 更新时间；同年为 `MM-DD HH:mm`，非同年为 `YYYY-MM-DD HH:mm` |
| `passcode` | string | 分享提取码；响应字段和分享链接均未携带时为空字符串 |

#### Agent 展示规则

有结果时必须以 Markdown 表格展示，表格有且只能包含三列，列顺序固定为：**分享标题**、**更新时间**、**分享链接**。不要展示 `pwd_id`、`passcode` 或其他字段，尤其不得新增提取码列。更新时间只使用 `updated_at` 字段。字段映射和展示方式如下：

| 表格列 | 字段 | 展示规则 |
|------|------|------|
| 分享标题 | `title` | 展示完整分享标题 |
| 更新时间 | `updated_at` | 直接展示 CLI 返回的可读时间；同年省略年份，非同年保留年份 |
| 分享链接 | `share_url` | 参考搜索结果的“查看链接”，必须渲染为可点击的 Markdown 蓝链 `[查看](share_url)`，不要直接展示裸 URL，也不要用代码格式包裹链接 |

展示示例：

| 分享标题 | 更新时间 | 分享链接 |
|------|----------|----------|
| 课程资料 | 2025-12-02 22:31 | [查看](https://pan.quark.cn/s/abc123) |

**成功示例**：

```jsonl
{"code":0,"msg":"成功","data":{"pwd_id":"abc123","share_url":"https://pan.quark.cn/s/abc123","title":"课程资料","updated_at":"2025-12-02 22:31","passcode":"xK9m"},"action":"get-share-update-list","type":"list"}
{"code":0,"msg":"获取第 1 页数据成功，本页 1 条，总数 1 条","data":{"total":1,"current_page":1,"has_next_page":false},"action":"get-share-update-list","type":"result"}
```

空列表时只输出最后一行 `result`，分页元数据仍保持完整。

#### 失败出参

| 错误码 | 场景 |
|--------|------|
| `-2201` | `--size` 不在 `1-50`，或不是正整数 |
| `-2202` | SDK 或分享模块初始化失败 |
| `-2203` | 请求分享更新列表时发生网络或运行时异常 |
| `-2204` | 接口响应不是有效对象 |
| `-2205` | 接口返回失败状态或缺少有效数据 |
| `-2206` | `--page` 不是正整数 |

接口返回有效 `errno` 时，最终 `code` 优先透传服务端错误码；`msg` 优先使用 `error_info`，其次使用 `agent_msg`。

```jsonl
{"code":-2201,"msg":"--size 必须为 1-50 的正整数","data":{},"action":"get-share-update-list","type":"result"}
{"code":-2206,"msg":"--page 必须为正整数","data":{},"action":"get-share-update-list","type":"result"}
```

---

### 获取分享链接更新文件（get-share-update-files）

获取用户指定分享链接中发生更新的文件。命令先调用 `getShareDetail` 获取 stoken；仅当分享详情没有返回有效 stoken 时，才通过 `/open/v1/share/saved/stoken` 按 `pwd_id` 兜底获取，然后调用更新文件接口。默认只查询一次，成功后展示最多 5 项更新文件表格，并原样展示结果的 `msg`；仅当用户明确要求查看更多时，才继续翻页请求更多数据。

#### Agent 调用流程

- 用户提供了明确的分享链接并询问“这个链接是否有更新”“更新了哪些文件”或“有哪些新增内容”时，直接调用本命令，不要先调用 `get-share-update-list`。
- `--url` 可直接使用 `get-share-update-list` 的 `share_url`。
- 命令不接收提取码参数。分享详情已返回 stoken 时不会再请求已转存令牌接口；详情无 stoken 时才按 `pwd_id` 回退查询。
- 未传 `--page` 时查询第 1 页。用户未明确要求查看更多时，只调用一次，展示本次返回的最多 5 项更新文件表格，并原样展示返回的 `msg`；不能仅因为 `total` 大于 5 或 `has_next_page` 为 `true` 就自行翻页。只有用户明确要求查看更多时，才使用下一页页码继续请求。
- 调用两个命令时都要按 Wild 模式要求附加 `--session-input` 与 `--session-id`。

#### 入参

```bash
node scripts/quark-drive.cjs get-share-update-files --url <URL> [--page <NUMBER>]
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--url <string>` | string | 必填 | — | 完整分享链接，命令从中解析 `pwd_id` |
| `--page <number>` | number | 选填 | `1` | 页码，从 1 开始；默认不传，仅在用户明确要求查看更多时用于请求下一页 |

```bash
# 公开分享
node scripts/quark-drive.cjs get-share-update-files --url "https://pan.quark.cn/s/abc123" --session-input "用户原始提问" --session-id "1784035443-a1b2c3"
```

#### 成功出参

最终输出一行 `type: "result"`。`data.files` 为最多 5 项的更新文件数组，`data.share_url` 为本次查询的完整分享链接。

`total` 完全使用服务端返回值；`current_page` 表示本次请求页码，`has_next_page` 仅作为服务端分页元数据，不能自动触发后续翻页请求。

| 字段 | 类型 | 说明 |
|------|------|------|
| `total` | number | 服务端返回的更新文件总数 |
| `current_page` | number | 当前页码 |
| `file_count` | number | 本次返回的文件数，最大为 5 |
| `has_next_page` | boolean | 服务端是否还有下一页；仅作元数据，用户明确要求查看更多时才据此翻页 |
| `share_url` | string | 本次查询使用的完整分享链接，供后续翻页或转存操作复用 |
| `files[].title` | string | 文件名 |
| `files[].size` | number | 文件大小，单位 B |
| `files[].file_type` | string | 可直接展示的中文内容类型：`文件夹`、`视频`、`音频`、`图片`、`文档`、`其他`、`压缩包` 或 `应用` |
| `files[].fid` | string | 文件 ID |

#### Agent 展示规则

当 `files` 非空时，必须先以 Markdown 表格展示更新文件，列顺序固定为：**文件名**、**文件大小**、**文件类型**。即使只有 1 条结果也必须使用表格。用户未明确要求查看更多时，表格最多展示本次返回的前 5 条，展示完成后不要根据 `total` 或 `has_next_page` 自行翻页；只有用户明确要求查看更多时，才继续请求并展示下一页。

| 表格列 | 字段 | 展示规则 |
|------|------|------|
| 文件名 | `files[].title` | 展示完整文件名 |
| 文件大小 | `files[].size` | 将字节数换算为人类可读单位（B、KB、MB、GB、TB），例如 `1572864` 展示为“1.5 MB”；文件夹可展示为“—” |
| 文件类型 | `files[].file_type` | 直接使用该中文字段展示；CLI 已完成类型解析，无需再次映射或转换 |

更新文件表格展示完成后，必须再将返回结果的 `msg` 字段作为独立内容完整、原样地展示给用户；表格和 `msg` 都是必需结果，禁止相互替代。有更新时，`msg` 已包含新增数量、分享链接和是否转存的询问；没有更新时，不展示空表格，只原样展示包含无更新说明的 `msg`。

禁止对 `msg` 进行概括、扩写、同义改写，禁止将其中的分享链接转换为 Markdown 链接，禁止给 `msg` 添加任何前后缀。用户明确要求查看更多并触发下一页查询时，每次成功结果仍须按相同规则展示该页文件表格，并完整原样展示该次返回的 `msg`。

后续继续翻页或转存时，优先复用返回的 `data.share_url`，不要从 `msg` 文本中解析分享链接。

如果用户在后续新指令中从已展示的更新文件里只选择部分文件转存，必须将 `data.share_url` 的值作为 `<URL>`，先调用 `get-share-saved-dir --url <URL>`。成功返回有效 `data.pdir_fid` 时，调用 `saveas --url <URL> --fid-list <选中的files[].fid> --to-pdir-fid <pdir_fid>`；没有返回、缺少有效 `pdir_fid` 或执行出错时，不得阻断转存，直接调用 `saveas --url <URL> --fid-list <选中的files[].fid>` 并省略目录参数。两种情况都禁止调用会转存全部新增内容的 `saveas-update`，且调用命令时必须携带 Wild 模式要求的公共参数。

展示示例：

| 文件名 | 文件大小 | 文件类型 |
|--------|---------:|----------|
| 课程第2讲.mp4 | 100 MB | 视频 |
| 讲义.pdf | 2 MB | 文档 |

检测到该分享链接相较于上次存入新增了2个文件，以下是其中2个的名称，是否要将所有文件直接存入。https://pan.quark.cn/s/abc123

```jsonl
{"code":0,"msg":"检测到该分享链接相较于上次存入新增了2个文件，以下是其中2个的名称，是否要将所有文件直接存入。https://pan.quark.cn/s/abc123","data":{"total":2,"current_page":1,"file_count":2,"files":[{"title":"课程第2讲.mp4","size":104857600,"file_type":"视频","fid":"file1"},{"title":"讲义.pdf","size":2097152,"file_type":"文档","fid":"file2"}],"has_next_page":false,"share_url":"https://pan.quark.cn/s/abc123"},"action":"get-share-update-files","type":"result"}
```

#### 失败出参

- 分享链接为空或格式无效、获取分享访问令牌失败、网络异常时返回对应的专用错误码。
- 服务端错误码 `41043` 表示链接从未转存，因此没有历史记录可用于检测更新。若用户只想查询更新，直接告知无法检测；若用户希望保存该链接，必须改用 `saveas` 完成首次转存，不能调用 `saveas-update`。
- 服务端错误码 `41040` 表示链接未更新。

| 错误码 | 场景 |
|--------|------|
| `-2001` | 分享链接为空或格式无效 |
| `-2002` | SDK 或分享模块初始化失败 |
| `-2003` | 获取分享访问令牌失败 |
| `-2004` | 请求分享更新文件时发生网络或运行时异常 |
| `-2005` | 接口响应格式异常或缺少更新数据 |
| `-2006` | 接口返回失败状态 |
| `-2007` | `--page` 不是正整数 |

`loadUpdateData` 优先处理服务端 `errno` 和 `error_info`：服务端返回有效值时，最终 `code` 与 `msg` 原样优先透传；只有服务端未提供有效错误信息时才使用上述本地错误码和默认文案。

```jsonl
{"code":-2001,"msg":"无效的分享链接 URL","data":{},"action":"get-share-update-files","type":"result"}
{"code":-2007,"msg":"--page 必须为正整数","data":{},"action":"get-share-update-files","type":"result"}
```

---

### 获取分享详情（share-detail）

获取分享链接的详细信息，包括文件列表。支持翻页和子目录浏览（融合了原 share-page 命令的能力）。通过网盘服协议请求，支持客态模式（无需登录）。用户只需传入完整的分享链接 URL，CLI 内部自动解析 pwd_id 和提取码。

智能路由逻辑：
- 首页场景（`page=1` 且 `pdir-fid=0`）：直接调用 `getShareDetail`（1 次请求，高效）
- 翻页/子目录场景（`page>1` 或 `pdir-fid≠0`）：先调 `getShareDetail` 获取 stoken，再调 `getSharePageDetail`（2 次请求）

#### 入参

```bash
node scripts/quark-drive.cjs share-detail --url <URL> [--page <NUMBER>] [--size <NUMBER>] [--pdir-fid <FID>]
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--url <string>` | string | 必填 | — | 分享链接 URL（如 `https://pan.quark.cn/s/xxx` 或带提取码 `https://pan.quark.cn/s/xxx?pwd=abcd`） |
| `--page <number>` | number | 选填 | `1` | 页码 |
| `--size <number>` | number | 选填 | `50` | 每页条目数 |
| `--pdir-fid <string>` | string | 选填 | `0` | 目录 ID（根目录为 `"0"`，进入子目录时传对应 FID） |

#### 成功出参

仅一行 `type: "result"`，无进度输出。

**result.data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `token_info` | object | 分享令牌信息，包含 `title`（分享标题）等 |
| `share_info` | object | 分享元信息（文件总数 `file_num` 等） |
| `file_count` | number | 当前页返回的文件数量 |
| `files` | array | 文件列表 |

**files 数组元素字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `fid` | string | 文件 ID |
| `filename` | string | 文件名 |
| `size` | number | 文件大小（字节） |
| `file_type` | string | 文件类型（`'0'`:文件夹 `'1'`:文件） |
| `category` | number | 文件分类 |
| `created_at` | number | 创建时间 |
| `updated_at` | number | 更新时间 |
| `share_fid_token` | string | 分享文件令牌（转存时需要） |

**成功示例（首页场景）**：

```jsonl
{"code":0,"msg":"成功","data":{"token_info":{"title":"我的分享"},"share_info":{"file_num":3},"file_count":3,"files":[{"fid":"file1","filename":"doc.pdf","size":1048576,"file_type":"1","category":4,"created_at":1700000000,"updated_at":1700000000,"share_fid_token":"token1"}]},"action":"share-detail","type":"result"}
```

**成功示例（翻页场景）**：

```jsonl
{"code":0,"msg":"成功","data":{"token_info":{"title":"我的分享"},"share_info":{"file_num":10},"file_count":5,"files":[{"fid":"file1","filename":"video.mp4","size":52428800,"file_type":"1","category":1,"created_at":1700000000,"updated_at":1700000000,"share_fid_token":"token1"}]},"action":"share-detail","type":"result"}
```

#### 失败出参

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -801 | --page 必须为正整数 | `--page` 参数不是正整数 |
| -802 | --size 必须为正整数 | `--size` 参数不是正整数 |
| -803 | 获取分享详情失败 | SDK `getShareDetail` 或 `getSharePageDetail` 返回 `status !== 0`，`msg` 附带 SDK 返回的 `errno` 和 `error_info` |
| -804 | 无效的分享链接 URL | `--url` 参数不是合法的夸克网盘分享链接 |
| -805 | 获取分享令牌失败 | 翻页/子目录场景下，内部调用 `getShareDetail` 获取 stoken 失败 |

**失败示例**：

```jsonl
{"code":-801,"msg":"--page 必须为正整数","data":{},"action":"share-detail","type":"result"}
```

```jsonl
{"code":-803,"msg":"获取分享详情失败: errno=41007, message=share not exist","data":{},"action":"share-detail","type":"result"}
```

```jsonl
{"code":-804,"msg":"无效的分享链接 URL: invalid-url","data":{},"action":"share-detail","type":"result"}
```

```jsonl
{"code":-805,"msg":"获取分享令牌失败: errno=41007, message=share not exist","data":{},"action":"share-detail","type":"result"}
```

---

### 分享内搜索（share-search）

在分享链接内搜索文件。支持客态模式（无需登录）。用户只需传入完整的分享链接 URL，CLI 内部自动获取 stoken。

#### 入参

```bash
node scripts/quark-drive.cjs share-search --url <URL> --keyword <KEYWORD> [--page <NUMBER>] [--size <NUMBER>]
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--url <string>` | string | 必填 | — | 分享链接 URL（如 `https://pan.quark.cn/s/xxx`） |
| `--keyword <string>` | string | 必填 | — | 搜索关键词 |
| `--page <number>` | number | 选填 | `1` | 页码 |
| `--size <number>` | number | 选填 | `50` | 每页条目数 |

#### 成功出参

仅一行 `type: "result"`，无进度输出。

**result.data 字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `file_count` | number | 搜索结果数量 |
| `files` | array | 文件列表（字段同 `share-detail`） |

**成功示例**：

```jsonl
{"code":0,"msg":"成功","data":{"file_count":2,"files":[{"fid":"file1","filename":"report.pdf","size":2097152,"file_type":"1","category":4,"created_at":1700000000,"updated_at":1700000000,"share_fid_token":"token1"}]},"action":"share-search","type":"result"}
```

#### 失败出参

| 错误码 | 默认错误信息 | 触发场景 |
|--------|-------------|---------|
| -1001 | --page 必须为正整数 | `--page` 参数不是正整数 |
| -1002 | --size 必须为正整数 | `--size` 参数不是正整数 |
| -1003 | 搜索分享文件失败 | SDK `searchShareFiles` 返回 `status !== 0`，`msg` 附带 SDK 返回的 `errno` 和 `error_info` |
| -1004 | 无效的分享链接 URL | `--url` 参数不是合法的夸克网盘分享链接 |
| -1005 | 获取分享令牌失败 | 内部调用 `getShareDetail` 获取 stoken 失败 |

**失败示例**：

```jsonl
{"code":-1001,"msg":"--page 必须为正整数","data":{},"action":"share-search","type":"result"}
```

```jsonl
{"code":-1003,"msg":"搜索分享文件失败: errno=41008, message=stoken invalid","data":{},"action":"share-search","type":"result"}
```

```jsonl
{"code":-1004,"msg":"无效的分享链接 URL: invalid-url","data":{},"action":"share-search","type":"result"}
```
