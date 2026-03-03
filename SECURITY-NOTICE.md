# 安全警告 / Security Notice

更新时间 / Last updated: 2026-03-03

---

## 中文

我们收到多起报告：有第三方 GitHub 仓库或下载链接冒用本项目名称，分发 ZIP 压缩包。  
该 ZIP 解压后包含 **Windows 可执行文件**（例如 `luajit.exe`、`lua51.dll`、`Launcher.cmd`，以及强混淆脚本 `cdef.txt`）。

**这不是本项目官方发布，存在极高恶意风险。请勿下载、解压或运行该 ZIP。**

### 官方渠道（仅以下为准）

- 项目主仓库：<https://github.com/yuzeguitarist/Deck>
- 官方 Releases：<https://github.com/yuzeguitarist/Deck/releases>
- 官方网站：<https://deckclip.app>

### 请注意

- 本项目是 macOS 应用；任何“Deck/DeckClipboard”相关下载只要包含 `.exe` / `.dll` / `.cmd` 等 Windows 文件，**都不是官方**。
- 请不要从第三方 fork 或镜像仓库 README 里的 “Download / Installation / Support” 按钮下载二进制文件。

### 如果你已经下载或运行过可疑 ZIP（Windows 用户）

1. 立刻退出运行并断开网络（或切换飞行模式）。
2. 删除下载的 ZIP 和解压目录。
3. 运行杀毒或全盘扫描（建议 Defender Offline Scan 或你正在使用的安全软件）。
4. 检查是否出现可疑计划任务或异常启动项；如发现异常，先隔离再处理。
5. 出于谨慎，尽快修改重要账号密码（尤其浏览器、密码管理器、邮箱），并检查是否有异常登录。

### 反馈与求助

如果你发现疑似冒用或恶意分发的仓库/链接，请在本仓库 Discussions 或 Issues 提供线索（不要直接上传可疑样本）。我们会协助收集证据并向平台举报。

---

## English

We have received multiple reports of third-party GitHub repositories/download links impersonating this project and distributing a ZIP package.  
After extraction, the ZIP contains **Windows executables** (for example, `luajit.exe`, `lua51.dll`, `Launcher.cmd`, and a heavily obfuscated script `cdef.txt`).

**This is NOT an official release of this project and is highly likely to be malicious. Do NOT download, extract, or run that ZIP.**

### Official channels (only trust these)

- Main repository: <https://github.com/yuzeguitarist/Deck>
- Official Releases: <https://github.com/yuzeguitarist/Deck/releases>
- Official website: <https://deckclip.app>

### Please note

- This project is a macOS app. Any “Deck/DeckClipboard” download containing `.exe` / `.dll` / `.cmd` Windows files is **NOT official**.
- Do not download binaries from “Download / Installation / Support” buttons in third-party forks or mirror repositories.

### If you already downloaded or ran a suspicious ZIP (Windows users)

1. Stop running it immediately and disconnect from the network (or switch to airplane mode).
2. Delete the ZIP file and extracted folder.
3. Run antivirus/full-disk scans (Defender Offline Scan is recommended, or your trusted security software).
4. Check for suspicious scheduled tasks and startup entries; isolate first if anything suspicious is found.
5. As a precaution, change important account passwords as soon as possible (especially browser, password manager, and email accounts), and review sign-in activity.

### Report and get help

If you find suspicious impersonation/malicious distribution repositories or links, please share clues in this repository’s Discussions/Issues (do not upload suspicious samples directly). We will help collect evidence and report them to the platform.
