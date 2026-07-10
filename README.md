# 夸克网盘官方Skill

在Agent中随时调用网盘文件，和AI一起管理你的网盘。

## 一键安装


```plaintext
npx skills add https://github.com/quark-clouddrive/quarkclouddrive_offical/skills --skill quarkclouddrive
```

首次使用时，Skill 会自动引导完成 CLI 工具安装和夸克网盘登录授权。

`install.sh` 会自动完成以下操作：

1.  检测运行环境（macOS / Linux / Windows）
    
2.  检测 Node.js >= 16，不满足则自动安装
    
3.  从服务端下载最新的 Skill 包并解压安装到 `~/.quarkclouddrive/`
    
4.  注册 `quarkclouddrive` 全局命令（符号链接或 PATH 追加）
    
5.  自检验证安装结果
    

> 夸克网盘独立端下载地址：[https://pan.quark.cn](https://pan.quark.cn/)

## 功能说明

✅ **通用能力：** 存储、下载、备份、分享文件、转存链接资源、移动文件、创建文件夹

✅ **AI高阶能力：** 智能搜索、相册整理、知识问答

## 功能示例

**文件存储：** 对话中的文件可以直接存储到夸克网盘

```plaintext
每天美股收盘后，帮我做好当天大盘总结后存在夸克网盘「美股日报」文件夹
```

**文件下载：** 网盘中的文件支持下载到本地

```plaintext
下载夸克网盘里Q2季度总结的PPT
```

**文件备份：** 将本地文件备份到夸克网盘

```plaintext
每天18:00把C盘里「项目资料」文件夹里的文件备份到夸克网盘
```

**文件分享：** 将网盘中的文件生成分享链接

```plaintext
把上周末和朋友在上海外滩的照片，生成夸克网盘的分享链接
```

**文件转存：** 转存网盘分享链接中的文件到夸克网盘

```plaintext
把这份资料存到我的夸克网盘：http://pan.quark.cn/s/xxx
```

**文件移动：** 移动网盘中的文件

```plaintext
把网盘里的论文终稿移动到「毕业资料」文件夹里
```

**相册整理：** 支持按时间、地点、人物整理网盘相册（移动整理、复制整理）

```plaintext
把网盘里「春蕾幼儿园」文件夹下的照片，按照人物整理一下
```

**相册搜索：** 支持按时间、地点、场景、人物等多维度搜索网盘图片

```plaintext
把夸克网盘里存的去年和家人在三亚海边的合影找出来，做一个电子相册
```

**资料搜索：** 支持按文件名、主题、类型等维度搜索网盘资料

```plaintext
找一下夸克网盘里金字塔原理相关的PDF文件
```

**知识问答：** 支持根据网盘中存的文件直接发起问答

```plaintext
帮我对比一下夸克网盘里存的今年和去年的体检报告，总结一下有哪些需要注意的
```

## 安全设计

| **特性** | **说明** |
| --- | --- |
| OAuth 2.0 授权 | 浏览器 OAuth 授权码模式认证，不存储用户密码 |
| 无删除操作 | 不提供删除命令，从根本上防止误删 |
| 修改前确认 | 移动、覆盖等操作执行前须用户确认 |
| Token 保护 | 配置文件含 Token，Agent 禁止读取或输出其内容 |
| 授权码安全传递 | 支持浏览器自动授权与手动授权码两种方式 |
| 卸载需二次确认 | 卸载属不可逆操作，执行前必须向用户二次确认 |
| 多 Agent 隔离 | 各 Agent 配置独立，卸载不影响其他 Agent |

## 系统支持

| **平台** | **架构** | **状态** |
| --- | --- | --- |
| macOS | arm64 / amd64 | ✅ |
| Linux | arm64 / amd64 | ✅ |
| Windows (WSL) | amd64 | ✅ |
| Windows (原生) | — | ❌ |

> 要求 Node.js >= 16，安装脚本会自动检测并安装。

## 故障排除

遇到问题时，直接对 Skill 说：

*   **Token 过期** — "夸克网盘授权过期了" → 自动引导重新登录
    
*   **检查状态** — "查看我的网盘账号信息" → 显示当前账号与会员状态
    
*   **更新 Skill** — "更新夸克网盘 Skill" → 重新执行 install.sh 完成升级
    
*   **取消授权** — "取消夸克网盘授权" → 引导在夸克网盘 App 中完成解绑
    
*   **卸载 Skill** — "卸载夸克网盘 Skill" → 二次确认后完成完整卸载
    

> **升级约定**：更新 Skill 时必须执行 `bash install.sh`，由脚本进入更新模式完成覆盖安装。`quarkclouddrive update` 命令仅更新 CLI 本体，不会同步更新 Skill 文档。

## 项目结构

```plaintext
quarkclouddrive_offical/
├── SKILL.md                        # Skill 定义（Agent 行为规范）
├── install.sh                      # 安装 / 升级脚本
├── uninstall.sh                    # 卸载脚本
├── LICENSE                         # Apache License 2.0
├── README.md                       # 项目说明
└── references/                     # 参考文档
    ├── auth.md                     # 认证与账号管理
    ├── assistant.md                # AI 助手（文件总结与知识问答）
    ├── file-ops.md                 # 文件操作（创建文件夹、移动、下载）
    ├── file-organize.md            # 相册整理
    ├── file-read.md                # 文件读取
    ├── file-saveas.md              # 转存分享链接
    ├── file-search.md              # 文件检索
    ├── file-share.md               # 文件分享
    └── file-upload.md              # 文件上传

```

## 许可证

[Apache License 2.0](./LICENSE)
