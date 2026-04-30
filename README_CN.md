<a href="https://deckclip.app/zh-cn">
    <img width="1024" alt="Deck，现代、原生、隐私优先的 macOS 剪贴板管理器" src="photos/Deck.webp">
</a>

<p align="center">
  <a href="#功能特性">功能特性</a> ·
  <a href="#安装">安装</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#联动">联动</a> ·
  <a href="#截图">截图</a> ·
  <a href="https://deckclip.app/zh-cn/docs">文档</a> ·
  <a href="#支持作者">支持作者</a> ·
  <a href="#许可证">许可证</a> ·
  <a href="https://deckclip.app/zh-cn">网站</a> ·
  <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://deckclip.app/zh-cn">
    <img src="https://img.shields.io/badge/platform-macOS_14+-blue?style=flat-square" alt="macOS 14+ 剪贴板管理器">
    <img src="https://img.shields.io/badge/swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="基于 Swift 5.9+ 构建">
    <img src="https://img.shields.io/badge/license-AGPL_v3_%26_ARR-blue?style=flat-square" alt="deckclip AGPLv3，其他 ARR">
  </a>
</p>

---

<a id="功能特性"></a>
## 功能特性

### 剪贴板历史与搜索

- 记录文本、图片、文件、颜色、链接、富文本。
- 关键词、正则、类型筛选搜索，支持基于 NLEmbedding 的**语义搜索**（离线运行）。
- 斜杠 `/` 触发搜索规则：按应用、日期、类型过滤（支持排除与多值）。
- 每条记录可设置自定义标题，支持搜索，跨设备同步。
- 标签与智能分类。
- 上下文感知排序：根据当前应用自动调整剪贴板顺序。

### 智能功能

- **智能规则** — 条件匹配 + 动作执行的自动化工作流，支持 JavaScript 脚本插件。
- **OCR 文字识别** — 后台自动提取图片中的文字（基于 Vision 框架，支持多语言）。
- **光标助手** — 三连按 Shift 呼出，根据上下文推荐剪贴板内容，支持触发词匹配和模板联动。
- **模板库** — 保存常用剪贴板模板，支持颜色标记和光标位置粘贴。
- **文本转换** — JSON 格式化/压缩、Base64、URL 编解码、大小写转换、时间戳解析、MD5 哈希、行排序/去重等。
- **IDE 源码定位** — 从 VS Code、Xcode、JetBrains、Cursor、Windsurf 复制时自动记录文件路径和行号，点击即可跳回源码。
- **Figma 识别** — 自动识别 Figma 剪贴板内容，提供专用预览。
- **链接预览** — 一键生成二维码。
- **链接净化** — 自动移除 URL 中的跟踪参数。
- **即时计算** — 复制数学表达式，立即显示计算结果。
- **智能文本检测** — 识别邮箱、URL、电话号码、编程语言、JWT Token 等。

### 隐私与安全

- **本地优先** — 数据默认留在你的 Mac 上。
- **Touch ID / Face ID** 解锁面板。
- **敏感信息过滤** — 通过 Luhn 算法自动识别银行卡号和身份证/护照号，跳过记录。
- **窗口感知保护** — 检测到密码输入、登录页面等敏感窗口标题时自动暂停记录。
- **剪贴板隐写** — 在图片或零宽文本中嵌入隐藏信息。
- **屏幕共享检测** — 在屏幕共享或录屏时可自动隐藏面板。
- **暂停模式** — 一键暂停剪贴板记录。

### 同步与共享

- **iCloud 同步** — 基于 CloudKit，支持可选的端到端加密。
- **局域网共享** — AES-GCM 加密 + TOTP 验证。
- **直连模式** — 通过 IP 地址直接连接，绕过 VPN 或 Bonjour 限制。

### 工作流

- **队列模式** — 按顺序依次粘贴多条内容。
- **键盘优先**设计，可选 Vim 模式。
- **打字粘贴** — 逐字符输入剪贴板内容（适配不支持直接粘贴的场景）。
- **Siri 快捷指令** — 通过 App Intents 查询最近的剪贴板条目。
- **CLI Bridge** — 终端调用，用于本地自动化和外部联动。
- **数据导出** — 导出剪贴板历史。
- **使用统计** — 纯本地计算，不上传任何数据。
- 支持从 Paste、Maccy、CopyClip 等剪贴板应用迁移历史。
- 自动更新（每日检查 + 设置页手动检查）。
- 文件缺失提示，面板关闭后自动清理。

<a id="联动"></a>
## 联动

- **[Deck × Orbit](https://github.com/yuzeguitarist/Orbit)** — 径向应用切换器 + 文件中转。鼠标附近呼出、长按触发、拖拽退出、文件 AirDrop/删除。

<a id="安装"></a>
## 安装

> **临时说明：** 目前请不要下载或更新 Deck。如果你当前安装的版本还能正常使用，请继续使用现有版本，并暂时不要使用软件内自动更新。

### Homebrew

```bash
brew tap yuzeguitarist/deck
export HOMEBREW_CASK_OPTS="--no-quarantine"
brew install --cask deckclip
```

`HOMEBREW_CASK_OPTS="--no-quarantine"` 会为这次 Homebrew Cask 安装关闭 macOS quarantine，因为 Deck 目前还没有完成公证。

### 手动安装

1. 从 [Releases](https://github.com/yuzeguitarist/Deck/releases) 下载最新 `.dmg`。
2. 将 `Deck.app` 拖入 **Applications**。
3. 在 `系统设置 → 隐私与安全性` 中授予**辅助功能**（及可能的**输入监控**）权限。

### 首次启动

正常情况下，首次打开时，macOS 会提示 **「无法打开"Deck"，因为 Apple 无法检查其是否包含恶意软件。」** 这是因为 App 未通过 Apple 付费开发者计划的公证，本项目源码公开，可以放心使用。

正常情况下，解决方法是：前往 **系统设置 → 隐私与安全性**，向下滚动找到关于 Deck 的提示，点击 **仍要打开** 即可。

**当前临时例外：** 由于上面提到的安装包问题，现在新下载或更新后的版本仍然可能无法打开。如果你当前安装的旧版本还能正常使用，请先继续使用旧版本，并**暂时不要使用软件内自动更新**。

> 源码公开仅供查看参考，请使用 Releases 里的官方编译版 App。

## 系统要求

- macOS 14.0+
- Apple Silicon 或 Intel

<a id="快速开始"></a>
## 快速开始

1. 启动 Deck。
2. `Cmd + P` 打开面板。
3. 方向键选择，回车粘贴。

### 默认快捷键

| 快捷键 | 功能 |
|--------|------|
| `Cmd + P` | 打开 Deck |
| `Enter` | 粘贴选中项 |
| `Shift + Enter` | 粘贴为纯文本 |
| `Cmd + 数字` | 快速粘贴 (1–9) |
| `Option + Q` | 切换队列模式 |
| `Space` | 切换预览 |
| `Esc` | 关闭 |

- 打开面板后直接输入即可搜索。
- 在历史列表上滚动鼠标滚轮可切换聚焦条目。

更多快捷键与 Vim 模式详见设置。

<a id="截图"></a>
## 截图

<p align="center">
  <a href="https://deckclip.app/zh-cn">
    <img src="photos/DeckView.webp" alt="Deck macOS 剪贴板管理器主界面，展示剪贴板历史搜索与预览" width="1024">
  </a>
</p>
<p align="center">
  <a href="https://deckclip.app/zh-cn">
    <img src="photos/ai-chat.webp" alt="Deck AI 剪贴板助手" width="1024">
  </a>
</p>

<a id="支持作者"></a>
## 支持作者

<p align="center">
  <strong>如果 Deck 对你有帮助，欢迎支持一下持续开发：</strong>
</p>

<p align="center">
  <a href="https://deckclip.app/zh-cn/support-development">
  <img src="photos/buy_me_a_coffee.webp" alt="微信/支付宝赞助收款码" width="420">
  </a>
</p>

<p align="center">
  微信 / 支付宝扫码赞助
</p>

<p align="center">
  海外用户可通过 Ko-fi 赞助
</p>

<p align="center">
  <a href="https://ko-fi.com/yuzeguitar">
    <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Ko--fi-FF5E5B?style=for-the-badge&logo=kofi&logoColor=white" alt="Ko-fi 赞助">
  </a>
</p>

<a id="许可证"></a>
## 许可证

本项目采用**双许可证**策略：

- `Deck/deckclip` 目录下的代码以 **GNU AGPL v3.0 only** 发布 — 详见 [`deckclip/LICENSE`](deckclip/LICENSE)。
- 其他目录与文件为 **源码可见**，并且 **保留所有权利（All Rights Reserved）** — 详见 [LICENSE](LICENSE)。

### 使用与权利说明

- 本仓库公开源码，仅供查看与参考。
- 未经作者书面许可，不授予对源码的使用、修改、再分发或商业化权利。
- 你可以使用作者发布的官方编译版 Deck App。
- 欢迎通过 Issue 提交反馈或问题报告，但本仓库不接受 Pull Request。

如有疑问或授权需求，请联系：hi@deckclip.app

## 支持

- [报告 Bug](https://github.com/yuzeguitarist/Deck/issues/new?template=bug_report_cn.yml)
- [功能建议](https://github.com/yuzeguitarist/Deck/issues/new?template=feature_request_cn.yml)
- [讨论区](https://github.com/yuzeguitarist/Deck/discussions)
- 本仓库不接受 Pull Request

---

## GitHub 星标历史图表

<a href="https://deckclip.app/zh-cn">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/image?repos=yuzeguitarist/Deck&type=timeline&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/image?repos=yuzeguitarist/Deck&type=timeline&legend=top-left" />
   <img alt="Deck macOS 剪贴板管理器 GitHub 星标历史" src="https://api.star-history.com/image?repos=yuzeguitarist/Deck&type=timeline&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  版权所有 © 2024-2026 Yuze Pan. 保留一切权利。
</p>
