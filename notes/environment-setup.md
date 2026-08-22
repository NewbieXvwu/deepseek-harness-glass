# 开发环境与官方参考记录

**记录日期：** 2026-08-21（GMT+8）

本仓库在 `main` 分支工作，实际工作树为 `/home/ubuntu/work/deepseek-harness-glass`。
官方 DeepSeek Harness 参考源码已单独克隆到 `/home/ubuntu/work/deepseek-harness-reference`，远端为 [`deepseek-ai/DeepSeek-Harness`](https://github.
com/deepseek-ai/DeepSeek-Harness)。
参考仓库的当前克隆提交记录为 `b150a55`；项目任务验收仍以 `TODO.md` 中锁定的官方基线 `528c682e061696f5a160f363f236ecbf53cbd006` 为准，若需要源码级对照，应先切换或读取该锁定提交，而不能把 HEAD 自动当作规格版本。

Swift 安装遵循 [Swift 官方 Ubuntu 24.04 安装页面](https://swift.org/install/linux/ubuntu/24_04/)，当前使用官方 Swift 6.3.3 Ubuntu 24.04 x86_64 tarball。
由于 Linux 环境只能验证 Foundation/SwiftPM 可移植路径，macOS 26、Xcode 26、Apple Silicon 的 AppKit/SwiftUI、WindowServer 截图、辅助功能和视觉门禁仍必须由项目既有 macOS 工作流验证；
Linux 编译成功不得替代该证据。

初次执行官方安装脚本时，下载入口返回 HTTP 403；随后改用同一官方安装页列出的版本化 tarball，并保留下载日志。该替代路径不改变项目支持边界，也不引入第三方工具链。

| 项目 | 当前事实 | 验收边界 |
|---|---|---|
| 目标分支 | `main` | 所有任务提交必须落在此分支 |
| 目标仓库 | `NewbieXvwu/deepseek-harness-glass` | 以 `origin` 为推送目标 |
| 官方参考 | `deepseek-ai/DeepSeek-Harness` | 规格仍以 `TODO.md` 锁定 commit 为准 |
| Swift | 官方 Swift 6.3.3 Ubuntu 24.04 x86_64 | 仅用于 Linux 可移植门禁；原生门禁仍在 macOS 26 |
| Host/UI 基线 | macOS 26、Xcode 26、Apple Silicon | 由 GitHub Actions 权威验证 |

本记录只描述环境事实，不将环境准备本身误报为任何产品 TODO 的完成证据。
