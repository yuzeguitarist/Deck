<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="photos/deck-macOS-Dark-1024x1024@1x.png">
    <source media="(prefers-color-scheme: light)" srcset="photos/deck-macOS-Default-1024x1024@1x.png">
    <img src="photos/deck-macOS-Default-1024x1024@1x.png" alt="Deck Logo" width="128" height="128">
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">
  <strong>A modern, native, privacy-first clipboard OS for macOS</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#usage">Usage</a> •
  <a href="#tech-highlights">Tech</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#license">License</a> •
  <a href="#中文说明">中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_14+-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/license-GPL--3.0-green?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/status-Free_for_now-brightgreen?style=flat-square" alt="Status">
</p>

<p align="center">
  <img src="photos/DeckShow.png" alt="Deck Show" width="720">
</p>

---

## Features (all currently free)

- **Instant history** – Never lose copied text, images, links, files.
- **Fuzzy search & filters** – Find any clip in milliseconds.
- **Biometric lock + encryption** – CryptoKit AES-GCM + Keychain storage; Touch ID unlock.
- **Smart rules / context awareness** – App-aware filters, formatting, routing.
- **Scriptable pipeline** – Plugin-style automation for clipboard workflows.
- **Rich previews** – Links, PDFs, images with inline preview overlay.
- **LAN sharing (P2P)** – Local network send/receive without cloud.
- **Keyboard-first** – Global hotkeys, Vim-like navigation, zero-click flow.
- **Native macOS** – SwiftUI + AppKit polish, follows system theme.

> Deck is free right now; advanced features may become Pro later, but are unlocked in the current release.

### Why Deck beats typical clipboard managers
- Local-first, encrypted by default; no cloud dependency.
- Context-aware + smart rules that adapt per app/content.
- Plugin/script hooks to extend behaviors instead of a closed box.
- LAN P2P sharing for teams/offline scenarios (no account needed).
- Rich previews and large-payload handling without lag.

## Installation

### Manual Download

Download the latest `.dmg` from [Releases](https://github.com/yuzeguitarist/Deck/releases).

### Homebrew (coming)

```bash
brew install --cask deck
```

### Source

The source is partially published; a full build from source is not supported yet. Please use the packaged `.dmg` for now.

### Install on macOS without a paid developer account

Because the app is not signed or notarized, Gatekeeper will warn. Follow these steps:

1) Download the latest `.dmg` from Releases.  
2) Open the DMG and drag `Deck.app` to Applications (or the `Applications` link in the DMG).  
3) First launch (bypass Gatekeeper): in Applications, **Control+Click (or right-click) Deck → Open**, confirm the warning and click “Open”. If blocked, go to `System Settings → Privacy & Security` and click “Allow Anyway” / “Open Anyway”, then open once more.  
4) Permissions: grant **Accessibility** (and **Input Monitoring** if prompted) in `System Settings → Privacy & Security` so global hotkeys and paste work. Restart Deck after granting.  
5) Updates: for each new DMG, drag to Applications to replace. If Gatekeeper warns again, repeat step 3.  
6) Remove quarantine if you see “file is damaged”:  
   ```bash
   sudo xattr -r -d com.apple.quarantine /Applications/Deck.app
   ```  
   then Control+Click → Open once.  
7) Uninstall: quit Deck, delete `Applications/Deck.app`. To erase data, delete `~/Library/Containers/com.yuzeguitar.Deck` (this removes history/settings).

FAQ (unsigned builds):
- Why the warning? Not signed/notarized (no paid dev account). Use the “Open anyway” flow above.  
- Is it safe? Deck runs locally, stores history encrypted (CryptoKit AES-GCM + Keychain, Touch ID unlock). Download only from the official Releases page.  
- Intel support? Yes, universal binary (arm64 + x86_64).  
- Need internet? Core features are local; LAN sharing needs local network only.  
- What if I skip permissions? Without Accessibility/Input Monitoring, global hotkeys/paste helpers are limited; you can grant later in Privacy & Security.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

## Usage

1. Launch Deck
2. Grant Accessibility permissions when prompted
3. Use `Cmd + P` to open clipboard history
4. Start copying — Deck remembers everything, encrypted at rest

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd + P` | Open Deck |
| `Left / Right` | Navigate items |
| `Enter` | Paste selected |
| `Shift + Enter` | Paste as plain text |
| `Cmd + Number` | Quick paste (1-9) |
| `Cmd + C` | Copy selected and close |
| `Cmd + Q` | Toggle queue mode |
| `Space` | Toggle preview |
| `Delete` | Delete selected |
| `Esc` | Close |

**Vim Navigation** (when enabled in settings):

| Shortcut | Action |
|----------|--------|
| `j` | Move right |
| `k` | Move left |
| `/` | Focus search |
| `x` | Delete selected |
| `y` | Copy and move to top |

## Screenshots

<p align="center">
  <img src="photos/DeckView.png" alt="Deck main view" width="720">
</p>
<p align="center">
  <img src="photos/DeckSettings.jpg" alt="Deck settings" width="720">
</p>

## Tech Highlights

- **Swift 5.9+ with SwiftUI + AppKit bridging** for native UX and performance.
- **CryptoKit AES-GCM + Keychain + LocalAuthentication** for encrypted history with Touch ID unlock.
- **SQLite-based storage** with custom migration/compaction via `DeckSQLManager`.
- **Plugin/script engine** to automate transforms and workflows.
- **Local-first architecture**: no external cloud; optional LAN P2P sharing.

## Contributing

We welcome contributions to the open-sourced parts! Please read our [Contributing Guide](CONTRIBUTING.md) before submitting a PR.

> **Note**: All PRs must target the `dev` branch, not `main`.

### Quick Start

1. Fork the repository
2. Clone and sync with upstream `dev` branch
3. Create your feature branch (`git checkout -b feature/amazing-feature dev`)
4. Run code quality script: `./scripts/code-quality.sh` (score >= 80 required)
5. Push to your fork
6. Open a Pull Request to `dev` branch

## License

This project is **partially open source** under **GPL-3.0 with Commons Clause** – see [LICENSE](LICENSE).

> Scope: Open modules include scripting hooks, data export, SQL layer, security/encryption utilities, and shared utilities. Core UI/UX, premium logic, and certain services stay proprietary.

**TL;DR**
- Free to use for personal, non-commercial purposes.
- Free to modify and learn from the open-sourced parts.
- Derivative works must be open-sourced under the same license.
- Cannot be sold or used commercially without permission.
- Core/Pro features are not included in this repository.

For commercial licensing, contact: yuzeguitar@gmail.com.

## Support

- [Report Bug](https://github.com/yuzeguitarist/Deck/issues/new?template=bug_report.md)
- [Request Feature](https://github.com/yuzeguitarist/Deck/issues/new?template=feature_request.md)
- [Discussions](https://github.com/yuzeguitarist/Deck/discussions)

## Contributors

Thanks to all the amazing people who have contributed to Deck!

感谢所有为 Deck 做出贡献的人！

<!-- ALL-CONTRIBUTORS-LIST:START -->
<!-- ALL-CONTRIBUTORS-LIST:END -->

## Acknowledgments

- Thanks to all [contributors](https://github.com/yuzeguitarist/Deck/graphs/contributors)
- Built with SwiftUI

---

# 中文说明

<p align="center">
  <strong>一款原生、注重隐私的 macOS 剪贴板 OS</strong>
</p>

## 功能特性（当前全部免费）

- **即时历史**：文本、图片、链接、文件统统记住。
- **模糊搜索/筛选**：毫秒级定位需要的内容。
- **加密 + 生物识别解锁**：CryptoKit AES-GCM，Keychain 存储，Touch ID 解锁。
- **智能规则 / 上下文感知**：按应用/内容自动格式化、路由。
- **可编排的脚本管线**：插件式脚本自动化工作流。
- **富预览**：链接、PDF、图片直接预览。
- **局域网 P2P 共享**：本地传输，无需云和账号。
- **键盘优先**：全局热键、类 Vim 导航，零点击高效操作。
- **原生体验**：SwiftUI + AppKit 打磨，跟随系统主题。

> 当前版本全部功能免费，后续高级特性可能转为 Pro，但现在已解锁。

### 为什么比普通剪贴板更强
- 本地优先 + 默认加密，无云依赖。
- 上下文智能与规则引擎，按应用/内容自适应。
- 开放插件/脚本接口，可扩展而非黑盒。
- 局域网 P2P 共享，团队/离线场景更好用。
- 大量内容与预览仍保持顺滑。

## 安装方式

### 手动下载

从 [Releases](https://github.com/yuzeguitarist/Deck/releases) 获取最新 `.dmg`。

### Homebrew（即将上线）

```bash
brew install --cask deck
```

### 源码

当前仅部分源码公开，尚不支持完整从源码自行构建，请先使用发布的 `.dmg`。

### 安装指引（macOS 14+）

1) 下载：从 Releases 获取最新 `.dmg`。  
2) 安装：打开 DMG，将 `Deck.app` 拖到左侧或窗口内的 `Applications`。  
3) 首次启动（绕过 Gatekeeper）：在“应用程序”中 **按住 Control 点击 Deck → 打开**（或右键→打开），出现“来自身份不明开发者”时选择继续打开。若仍被拦截，去 `系统设置 → 隐私与安全性`，点击“仍要打开/允许”，再回到应用程序里打开一次。  
4) 权限：按提示在 `隐私与安全性` 中勾选 Deck 的 **辅助功能**（必要）和 **输入监控**（若提示），确保全局快捷键与粘贴功能正常；授权后重启 Deck。  
5) 更新：下载新版 DMG，拖入 Applications 覆盖旧版。如再提示安全警告，重复步骤 3。  
6) 若出现“文件已损坏”提示：终端执行  
   ```bash
   sudo xattr -r -d com.apple.quarantine /Applications/Deck.app
   ```  
   然后再 Control+点击 → 打开。  
7) 卸载：退出 Deck，删除 `Applications/Deck.app`。如需清空数据，删除 `~/Library/Containers/com.yuzeguitar.Deck`（会移除历史和设置，谨慎操作）。

#### 常见问答（未签名包）
- 为什么会提示“无法验证开发者/文件已损坏”？按上面的“仍要打开”/xattr 处理即可。  
- 是否安全？应用本地运行，历史加密存储（CryptoKit AES-GCM + Keychain，Touch ID 解锁）。只从官方 Releases 下载。  
- Intel 能用吗？可以，二进制为通用架构（arm64 + x86_64）。  
- 需要联网吗？核心功能本地运行；局域网分享需局域网，不依赖云。  
- 不给权限会怎样？不授予“辅助功能/输入监控”则全局快捷键、自动粘贴等受限，随时可在“隐私与安全性”补授权。
## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Apple Silicon 或 Intel Mac

## 使用方法

1. 启动 Deck
2. 根据提示授予辅助功能权限
3. 使用 `Cmd + P` 打开剪贴板历史
4. 开始复制 —— Deck 会加密保存你的全部剪贴板历史

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Cmd + P` | 打开 Deck |
| `Left / Right` | 左右导航 |
| `Enter` | 粘贴选中项 |
| `Shift + Enter` | 粘贴为纯文本 |
| `Cmd + 数字` | 快速粘贴 (1-9) |
| `Cmd + C` | 复制选中项并关闭 |
| `Cmd + Q` | 切换队列模式 |
| `Space` | 切换预览 |
| `Delete` | 删除选中项 |
| `Esc` | 关闭 |

**Vim 导航模式**（在设置中启用后）:

| 快捷键 | 功能 |
|--------|------|
| `j` | 向右移动 |
| `k` | 向左移动 |
| `/` | 聚焦搜索框 |
| `x` | 删除选中项 |
| `y` | 复制并移到顶部 |

## 截图

<p align="center">
  <img src="photos/DeckView.png" alt="Deck 主界面" width="720">
</p>
<p align="center">
  <img src="photos/DeckSettings.jpg" alt="Deck 设置" width="720">
</p>

## 技术亮点

- **Swift 5.9+，SwiftUI + AppKit 桥接**，原生性能与体验。
- **CryptoKit AES-GCM + Keychain + 生物识别**，本地加密与 Touch ID 解锁。
- **SQLite 存储**，`DeckSQLManager` 负责迁移与压缩。
- **插件/脚本引擎**，支持自动化处理剪贴板。
- **本地优先架构**：无外部云依赖，可选局域网 P2P。

## 参与贡献

欢迎为开源部分贡献代码！请先阅读 [贡献指南](CONTRIBUTING.md)。

> **注意**：所有 PR 必须提交到 `dev` 分支，而不是 `main`。

### 快速开始

1. Fork 本仓库
2. 克隆并同步上游 `dev` 分支
3. 从 dev 创建功能分支 (`git checkout -b feature/amazing-feature dev`)
4. 运行代码质量脚本：`./scripts/code-quality.sh`（评分需 >= 80）
5. 推送到你的 Fork
6. 向 `dev` 分支发起 Pull Request

## 许可证

本项目为 **部分开源**，采用 **GPL-3.0 + Commons Clause** 许可证 - 详见 [LICENSE](LICENSE)。

> 开源范围：脚本接口、导出、SQL 存储、加密安全和部分工具；核心 UI/UX、增值逻辑等保持闭源。

**简单来说：**
- 个人/非商业免费使用
- 可学习与修改开源部分
- 衍生作品需以相同许可证开源
- 未经许可不得销售或商业使用
- 核心/专业版功能未包含在本仓库

商业授权请联系：yuzeguitar@gmail.com

## 支持

- [报告 Bug](https://github.com/yuzeguitarist/Deck/issues/new?template=bug_report.md)
- [功能建议](https://github.com/yuzeguitarist/Deck/issues/new?template=feature_request.md)
- [讨论区](https://github.com/yuzeguitarist/Deck/discussions)

---

<p align="center">
  Made by <a href="https://github.com/yuzeguitarist">Yuze Pan (潘禹泽)</a>
</p>
