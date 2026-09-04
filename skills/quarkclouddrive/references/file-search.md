# 文件检索

所有 Search 与 `browse --all` 会自动完成服务端分页。成功时 stdout 输出 NDJSON `result` 和 `artifact`；`artifact.data.file_path` 指向包含完整结果的 JSONL 文件，每行一个 `BrowseFileItem`。

## 查询路由

按用户意图选择命令：

| 用户意图 | 命令 |
| --- | --- |
| 找到目标文件夹 | `search --keyword "<文件夹名>" --search-type dir` |
| 获取文件夹全部直接子项 | `browse --parent-fid "<folder_fid>" --all` |
| 在指定文件夹内按任意关键词搜索 | `search --parent-fid "<folder_fid>" --keyword "<关键词>"` |
| 文件夹内仅按类型或后缀筛选 | 先执行 `browse --parent-fid "<folder_fid>" --all`，再读取 Artifact 按返回字段筛选 |

文件夹匹配不唯一时先让用户确认。`browse --all` 只列出直接子项；带 `parent_fid` 的 Search 是直接子项还是整个子树由服务端决定，Agent 不递归补查。文件夹内关键词搜索必须传 `--parent-fid`，不能用本地文件名包含判断替代。

## 调用与结果范围边界

- Search 不设固定调用次数，只按用户尚未完成或已更新的检索条件执行。已有完整且匹配的 Artifact 时优先复用；禁止无新信息重复相同查询、无依据改词或仅为规避条数限制而机械拆分。
- 上一次调用因技术失败或未生成后续操作所需 Artifact 时，可以用相同条件重试。
- 聚合时只使用本次任务中、与用户当前请求范围逐一匹配的 Artifact；范围变化后废弃不再匹配的结果，禁止混入会话中的旧查询。

## Search

```bash
node scripts/quark-drive.cjs search \
  --keyword "<KEYWORD>" \
  [--parent-fid "<FOLDER_FID>"] \
  [--size <1-100>] \
  [--search-type <type>] \
  [--stdout-only]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--keyword` | — | 必填，搜索关键词，最大 50 字符 |
| `--parent-fid` | — | 可选，将搜索范围限定到指定文件夹 |
| `--size` | `100` | 单页大小，范围 1～100；不是结果总量上限 |
| `--search-type` | `mix` | 搜索类型：`mix`、`video`、`album`、`doc`、`audio`、`dir`、`package`、`other`、`app` |
| `--stdout-only` | 关闭 | 中间步骤使用，不展示搜索结果 |

所有 Search 都自动分页：CLI 使用 `has_more` 判断是否继续，并在后续页复用同一 `search_id`。空页或只有重复项的页不是失败。分页协议错误、任一页请求失败或 Artifact 写入失败时命令整体失败，不发布本次 Artifact。

提取 keyword 时保留用户原话中的主题和文件类型词。例如「康乃馨照片」应传完整关键词，不能删成「康乃馨」。找文件夹必须传 `--search-type dir`；用户明确要求单一支持类型时可传对应值（图片/相册用 `album`，文档用 `doc`）。多类型或无对应值（如种子）时保留类型词并使用默认 `mix`；只有用户明确要求分别查看不同结果集时才拆分。

搜索无结果是成功结果，不是命令失败：直接告知用户未找到匹配文件，不自行换词重搜；原请求还有其他检索条件时继续完成其余条件。

`--stdout-only` 的选择：

- 搜索结果就是最终交付：不传，展示搜索结果。
- Search 只是重命名、分享或 AI 助手等操作的中间步骤：传入。

Wild 调用命令时还须按主 Skill 约束传入本次用户原始提问和同一会话复用的公共参数。

## Browse

`browse` 的命令参数、单页输出、`--all`、`file/list` 分页及失败约束见 [file-ops.md](file-ops.md)。本文件只保留 Search/Browse 的查询路由与共同结果消费规则。

## Artifact 与预览

Search 的 Artifact 行示例：

```jsonl
{"code":0,"msg":"成功","data":{"file_path":"/absolute/path/results.jsonl","count":3200,"format":"jsonl","description":"完整查询结果"},"action":"search","type":"artifact"}
```

`browse --all` 输出相同结构，其中 `action` 为 `browse`；`action` 始终与实际执行的查询命令一致。

- `file_path`：JSONL 绝对路径。
- `count`：完整分页结果按完整 FID 去重后的条数。
- `format`：固定为 `jsonl`。
- `description`：Artifact 用途说明。

Search 和 `browse --all` 的完整结果只以 Artifact 为准。`data.total` 仅用于展示和诊断，不参与完整性判断。命令成功并发布 Artifact 即表示分页与落盘完成；缺少 Artifact 时不得用预览生成批量操作计划。

Wild 的 `data.file_list` 最多预览 5 条。纯搜索任务按 CLI 返回条目展示 Markdown 表格，不读取 Artifact 补充预览；完整候选只在后续操作时读取 Artifact。结果包含 `check_all_link` 时输出可点击链接和完整 URL，包含 `browse_hint` 时原样展示提示。

表格字段保持以下展示规则：

| 表格列 | 字段 | 展示规则 |
| --- | --- | --- |
| 缩略图 | `big_thumbnail` | 条件列；至少一条预览有非空值时才出现，并用 Markdown 图片展示。部分条目无值时该格留空；全部无值时删除整列，禁止虚构缩略图 |
| 文件名 | `filename` | 展示完整文件名 |
| 大小 / 文件数量 | `size` / `includeItems` | 表头保持“大小 / 文件数量”；文件的 `size` 转为人类可读单位，文件夹的 `includeItems` 展示为“xx 个文件” |
| 类型 | `category` / `obj_category` | 优先使用 `obj_category` 文案，否则将 category 0～8 映射为文件夹、视频、音频、图片、文档、种子、其他、压缩包、应用 |
| 修改时间 | `updated_at` | 将毫秒时间戳格式化为可读时间 |
| 查看链接 | `check_link` | 使用 Markdown 可点击链接；缺失时留空，禁止拼接或猜测 |

表格只展示 CLI 返回的预览条目；`data.total` 大于预览条数时说明“共找到 N 个文件，以上为部分结果”，但不读取 Artifact 补充表格。

## BrowseFileItem

Search 与 `browse --all` 的完整 Artifact 仅透传条目实际存在的字段，缺失字段不得猜测或补默认值。stdout 有界预览保持既有展示字段，不自动携带下表新增元数据。

Artifact 保留的 FileVO 字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `fid` | string | 文件 ID；接口操作始终使用完整值 |
| `parent_fid` | string | 父级目录 ID |
| `category` | int | 0 文件夹、1 视频、2 音频、3 图片、4 文档、5 种子、6 其他、7 压缩包、8 应用 |
| `filename` | string | 文件或文件夹名称 |
| `size` | int | 文件大小，单位 B |
| `content_hash` | string | 云端哈希，由夸克网盘自定义规则生成，服务端定义为相同物理文件唯一；重命名候选身份与去重仍只遵循 FID 规则，不使用该字段 |
| `file_type` | string | `"0"` 表示文件夹，`"1"` 表示文件 |
| `created_at` | long | 上传时间，毫秒时间戳 |
| `updated_at` | long | 修改时间，毫秒时间戳 |
| `full_path` | list of pair of string | 全路径；pair 的具体 JSON 结构未在协议中定义，保持服务端原始结构 |
| `format_type` | 协议未注明 | 文件详细格式；按服务端原值透传，不推断扩展名或 MIME，只有字符串值才可参与文件类型判断 |
| `duration` | int | 时长，单位秒 |
| `video_width` | int | 视频宽度 |
| `video_height` | int | 视频高度 |
| `video_max_resolution` | string | `low`、`normal`、`high`、`super`、`2k`、`4k`、`raw`、`unknown` 或 `unsupported` |
| `image_info.width` | int | 图片宽度；字段位于 `image_info` 嵌套对象中 |
| `image_info.height` | int | 图片高度；字段位于 `image_info` 嵌套对象中 |
| `l_shot_at` | int | 拍摄时间戳；当前 FileVO 协议未注明单位 |
| `series_info_v2.series_id` | string | 合辑 ID；字段位于 `series_info_v2` 嵌套对象中 |
| `series_info_v2.series_name` | string | 合辑名称；字段位于 `series_info_v2` 嵌套对象中 |
| `source_display` | string | 文件来源 |
| `upload_device` | string | 上传设备 |
| `shoot_device` | string | 拍摄设备 |
| `shoot_address` | string | 拍摄地点 |
| `file_local_path` | string | 服务端记录的本地存储路径 |

CLI 兼容与展示字段：

| 字段 | 说明 |
| --- | --- |
| `includeItems` | 文件夹包含数量，取自服务端 `include_items`，返回时才存在 |
| `obj_category` / `file` / `path` | 既有服务端条件字段，按原值使用；`path` 与 `full_path` 不得混为一谈 |
| `big_thumbnail` / `check_link` | Wild 展示字段，不参与文件身份判断 |

候选条目中实际存在且语义明确的 FileVO 元数据，可按用户明确的规则用于筛选、分组、排序或生成新名称。`content_hash` 即使相同也不得用于判断两个候选是同一文件或自动去重；跨 Artifact 去重仍只遵守下方 FID 规则。`parent_fid` 是目录 ID，不得当作可读目录名；`full_path` 和 `file_local_path` 只是服务端元数据，不代表 Agent 可访问的本机路径。字段结构、时间单位或含义无法可靠解释时不得猜测。默认预览和最终话术不得主动复述 `content_hash`、合辑 ID、完整路径或本地存储路径；用户明确要求核对依据时也只展示完成核对所需的信息。

## 聚合与 FID 去重

需要合并一个或多个 Artifact 时，在筛选、排序、编号和生成新名称之前完成全局去重：

1. FID 中存在 `|` 且最后一个 `|` 后有非空尾串时，以该原始尾串作为大小写敏感的文件指纹精确比较，不 trim、不转码。
2. 没有有效尾串时退化为按完整 FID 去重，不阻止生成计划。
3. 相同身份保留首次出现的条目，保持结果顺序稳定。
4. 指纹只用于本地识别同一文件；传给 Search、Browse、Rename 等接口的始终是完整 FID。

文件名中的 `|` 是普通字符，不参与 FID 指纹解析。重命名的确认、切批和提交规则见 [file-rename.md](file-rename.md)。
