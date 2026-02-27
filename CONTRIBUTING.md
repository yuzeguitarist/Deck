# Contributing to Deck | 贡献指南

[中文版](#中文版)

First off, thanks for taking the time to contribute!

> **Important**: This is a **partially open-source** project. Only non-core modules are available for contribution. Core features (context awareness, scripting engine, core UI/UX, etc.) are proprietary and not included in this repository.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Important Notes](#important-notes)
- [Development Setup](#development-setup)
- [Contribution Workflow](#contribution-workflow)
- [Code Quality Requirements](#code-quality-requirements)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Commit Guidelines](#commit-guidelines)

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Important Notes

### What You Can Contribute

- Bug fixes for open-sourced modules
- Documentation improvements
- Performance optimizations for open-sourced parts
- Localization / translations
- Test coverage improvements

### What You Cannot Contribute

- Core clipboard engine modifications
- Context awareness features
- Scripting engine
- Core UI/UX code and design assets
- Pro/paid feature implementations
- License key / activation system

## Development Setup

### Prerequisites

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+
- Git

### Setup Steps

1. **Fork the repository**

   Click the "Fork" button on GitHub to create your own copy.

2. **Clone your fork**

   ```bash
   git clone https://github.com/YOUR_USERNAME/Deck.git
   cd Deck
   ```

3. **Add upstream remote**

   ```bash
   git remote add upstream https://github.com/yuzeguitarist/Deck.git
   ```

4. **Sync with upstream dev branch**

   ```bash
   git fetch upstream
   git checkout -b dev upstream/dev
   ```

5. **Open in Xcode**

   ```bash
   open Deck.xcodeproj
   ```

6. **Build and run**

   Press `Cmd + R` in Xcode.

## Contribution Workflow

### Branch Strategy

```
main          <- Stable releases only (protected)
  |-- dev     <- Development branch (PR target)
       |-- feature/xxx  <- Your feature branches
       |-- fix/xxx      <- Your bugfix branches
```

### Step-by-Step Process

1. **Sync your fork with upstream**

   ```bash
   git fetch upstream
   git checkout dev
   git merge upstream/dev
   ```

2. **Create a feature branch from dev**

   ```bash
   git checkout -b feature/your-feature-name dev
   # or
   git checkout -b fix/your-bug-fix dev
   ```

3. **Make your changes**

   - Write clean, readable code
   - Add comments where necessary
   - Update documentation if needed

4. **Run code quality checks locally**

   ```bash
   # Run the code quality script (REQUIRED before pushing)
   ./scripts/code-quality.sh
   ```

   Your code must pass ALL checks:
   - Build succeeds without warnings
   - All tests pass
   - SwiftLint passes with no errors
   - Code quality score >= 80/100

5. **Commit your changes**

   Follow our [commit guidelines](#commit-guidelines).

   ```bash
   git add .
   git commit -m "feat(module): add your feature description"
   ```

6. **Push to YOUR fork**

   ```bash
   git push origin feature/your-feature-name
   ```

7. **Create Pull Request**

   - Go to your fork on GitHub
   - Click "Compare & pull request"
   - **Target branch: `yuzeguitarist/Deck:dev`** (NOT main!)
   - Fill out the PR template completely
   - Wait for review

## Code Quality Requirements

Before pushing to your fork, you MUST run the code quality script:

```bash
./scripts/code-quality.sh
```

### Quality Gates

| Check | Requirement |
|-------|-------------|
| Build | No errors, no warnings |
| Tests | All tests pass |
| SwiftLint | No errors (warnings OK) |
| Code Score | >= 80/100 |

### Quality Score Breakdown

- Build success: 25 points
- All tests pass: 25 points
- SwiftLint clean: 25 points
- Documentation: 15 points
- Test coverage: 10 points

**If your score is below 80, your PR will not be reviewed.**

## Pull Request Process

### PR Requirements Checklist

- [ ] PR targets `dev` branch (NOT `main`)
- [ ] Code quality script passes (score >= 80)
- [ ] All CI checks pass
- [ ] PR template is filled out completely
- [ ] Related issue is linked (if applicable)
- [ ] Documentation updated (if applicable)

### Review Process

1. Submit PR to `dev` branch
2. Automated CI checks run
3. Maintainer reviews code
4. Address any requested changes
5. Maintainer approves and merges
6. Your contribution will be included in the next release!

### After Merge

Your contribution may be credited in:
- Contributors list in README
- Release notes for the version including your changes
- GitHub Releases notes

## Coding Standards

### Swift Style Guide

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).

#### Naming

```swift
// Good
func fetchClipboardHistory() -> [ClipboardItem]
let isEnabled: Bool
class ClipboardManager

// Bad
func getHistory() -> [Any]
let enabled: Bool
class CBMgr
```

#### Formatting

- Use 4 spaces for indentation
- Maximum line length: 120 characters
- Use trailing closures when possible
- Group related code with `// MARK: -`

## Commit Guidelines

We use [Conventional Commits](https://www.conventionalcommits.org/).

### Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Code style (formatting, etc.) |
| `refactor` | Code refactoring |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Build process, dependencies |

### Examples

```bash
feat(clipboard): add image preview support
fix(search): resolve crash when query is empty
docs(readme): update installation instructions
```

---

# 中文版

首先，感谢你抽出时间来贡献！

> **重要提示**：本项目为 **部分开源**。仅非核心模块开放贡献。核心功能（上下文感知、脚本引擎、核心 UI/UX 等）为闭源，不包含在本仓库中。

## 目录

- [行为准则](#行为准则)
- [重要说明](#重要说明)
- [开发环境设置](#开发环境设置)
- [贡献工作流](#贡献工作流)
- [代码质量要求](#代码质量要求)
- [Pull Request 流程](#pull-request-流程)
- [代码规范](#代码规范)
- [提交规范](#提交规范)

## 行为准则

参与本项目的所有人都需要遵守我们的 [行为准则](CODE_OF_CONDUCT.md)。

## 重要说明

### 可以贡献的内容

- 开源模块的 Bug 修复
- 文档改进
- 开源部分的性能优化
- 本地化 / 翻译
- 测试覆盖率提升

### 不能贡献的内容

- 核心剪贴板引擎修改
- 上下文感知功能
- 脚本引擎
- 核心 UI/UX 代码与设计资源
- 专业版/付费功能实现
- 授权码/激活系统

## 开发环境设置

### 环境要求

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+
- Git

### 设置步骤

1. **Fork 仓库**

   点击 GitHub 上的 "Fork" 按钮创建你自己的副本。

2. **克隆你的 Fork**

   ```bash
   git clone https://github.com/你的用户名/Deck.git
   cd Deck
   ```

3. **添加上游远程仓库**

   ```bash
   git remote add upstream https://github.com/yuzeguitarist/Deck.git
   ```

4. **同步上游 dev 分支**

   ```bash
   git fetch upstream
   git checkout -b dev upstream/dev
   ```

5. **在 Xcode 中打开**

   ```bash
   open Deck.xcodeproj
   ```

6. **构建并运行**

   在 Xcode 中按 `Cmd + R`。

## 贡献工作流

### 分支策略

```
main          <- 仅稳定发布版本（受保护）
  |-- dev     <- 开发分支（PR 目标）
       |-- feature/xxx  <- 你的功能分支
       |-- fix/xxx      <- 你的修复分支
```

### 详细步骤

1. **同步你的 Fork 与上游**

   ```bash
   git fetch upstream
   git checkout dev
   git merge upstream/dev
   ```

2. **从 dev 创建功能分支**

   ```bash
   git checkout -b feature/你的功能名称 dev
   # 或
   git checkout -b fix/你的bug修复 dev
   ```

3. **进行更改**

   - 编写清晰、可读的代码
   - 必要时添加注释
   - 如需要，更新文档

4. **本地运行代码质量检查**

   ```bash
   # 运行代码质量脚本（推送前必须执行）
   ./scripts/code-quality.sh
   ```

   你的代码必须通过所有检查：
   - 构建成功且无警告
   - 所有测试通过
   - SwiftLint 无错误
   - 代码质量评分 >= 80/100

5. **提交更改**

   遵循我们的 [提交规范](#提交规范)。

   ```bash
   git add .
   git commit -m "feat(module): 添加你的功能描述"
   ```

6. **推送到你的 Fork**

   ```bash
   git push origin feature/你的功能名称
   ```

7. **创建 Pull Request**

   - 前往你在 GitHub 上的 Fork
   - 点击 "Compare & pull request"
   - **目标分支：`yuzeguitarist/Deck:dev`**（不是 main！）
   - 完整填写 PR 模板
   - 等待审核

## 代码质量要求

推送到你的 Fork 之前，必须运行代码质量脚本：

```bash
./scripts/code-quality.sh
```

### 质量门槛

| 检查项 | 要求 |
|--------|------|
| 构建 | 无错误、无警告 |
| 测试 | 所有测试通过 |
| SwiftLint | 无错误（警告可接受） |
| 代码评分 | >= 80/100 |

### 评分细则

- 构建成功：25 分
- 所有测试通过：25 分
- SwiftLint 通过：25 分
- 文档完整：15 分
- 测试覆盖率：10 分

**如果评分低于 80，你的 PR 将不会被审核。**

## Pull Request 流程

### PR 要求清单

- [ ] PR 目标为 `dev` 分支（不是 `main`）
- [ ] 代码质量脚本通过（评分 >= 80）
- [ ] 所有 CI 检查通过
- [ ] PR 模板完整填写
- [ ] 关联相关 Issue（如适用）
- [ ] 文档已更新（如适用）

### 审核流程

1. 提交 PR 到 `dev` 分支
2. 自动 CI 检查运行
3. 维护者审核代码
4. 处理任何修改请求
5. 维护者批准并合并
6. 你的贡献将包含在下一个版本中！

### 合并后

你的贡献可能会体现在：
- README 的贡献者列表
- 包含你更改的版本发布说明
- GitHub Releases 发布说明

## 代码规范

### Swift 风格指南

我们遵循 [Swift API 设计指南](https://swift.org/documentation/api-design-guidelines/)。

#### 命名

```swift
// 好
func fetchClipboardHistory() -> [ClipboardItem]
let isEnabled: Bool
class ClipboardManager

// 不好
func getHistory() -> [Any]
let enabled: Bool
class CBMgr
```

#### 格式

- 使用 4 个空格缩进
- 最大行长度：120 字符
- 尽可能使用尾随闭包
- 使用 `// MARK: -` 分组相关代码

## 提交规范

我们使用 [约定式提交](https://www.conventionalcommits.org/zh-hans/)。

### 格式

```
<类型>(<范围>): <描述>

[可选的正文]

[可选的脚注]
```

### 类型

| 类型 | 描述 |
|------|------|
| `feat` | 新功能 |
| `fix` | Bug 修复 |
| `docs` | 仅文档更改 |
| `style` | 代码风格（格式化等） |
| `refactor` | 代码重构 |
| `perf` | 性能优化 |
| `test` | 添加或更新测试 |
| `chore` | 构建过程、依赖等 |

### 示例

```bash
feat(clipboard): 添加图片预览支持
fix(search): 修复查询为空时的崩溃问题
docs(readme): 更新安装说明
```

---

有问题？欢迎在 [Discussions](https://github.com/yuzeguitarist/Deck/discussions) 中讨论！

感谢你的贡献！
