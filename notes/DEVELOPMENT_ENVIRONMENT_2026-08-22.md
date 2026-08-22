# 2026-08-22 开发环境与官方参考基线

## 已配置工具链

| 组件 | 固定版本或位置 | 验证状态 |
|---|---|---|
| Swift | `6.3.3`，`/opt/swift/usr/bin/swift` | 已安装；`swift --version` 确认为 `6.3.3-RELEASE`。 |
| Node.js | `24.19.0`，`/opt/node24/bin/node` | 已安装，符合锁定官方 Harness 的 Node `^22.19.0 \|\| >=24.0.0` engine 要求。 |
| Linux 构建依赖 | `build-essential`、`clang`、`binutils` | 已安装，修复 SwiftPM manifest 链接阶段缺少 C 编译器/链接器的问题。 |
| 官方 DeepSeek Harness | `/home/ubuntu/workspace/official-deepseek-harness` | 已锁定至 `528c682e061696f5a160f363f236ecbf53cbd006`，
已完成 `pnpm install --frozen-lockfile`。
|

## 官方参考的可执行核对

使用 Node 24.19.0 在锁定官方源码执行：

```bash
corepack pnpm exec vitest run packages/client/runtime/tests/partial.client.spec.ts
```

结果为 **1 个测试文件、9 项测试全部通过**。
覆盖内容包括 text/reasoning delta 的分 lane 累积、`block-end` 的整体替换、`finish` 不产生可见块变更、稀疏 index 压实和无变更时 snapshot 引用稳定性。该结果已在 T6.6 审计记录中引用。


## 本地验证边界

Linux 现在能够解析 SwiftPM manifest、解析 `swift-markdown@0.
8.0` 依赖并启动构建；但完整 `GlassSpec`/应用 target 使用 macOS 专有 **AppKit** 和 **SwiftUI**，Ubuntu 上的完整 `swift test` 会在 `import AppKit` 停止。
这是平台限制，不是项目实现的失败证据。

因此，Linux 继续用于 Foundation/PortableCore 独立编译与 Python/Node 规格门禁；
完整 AppKit、WKWebView 和 UI XCTest 的权威验证仍由当前提交对应的 `native-ui` macOS-26 工作流承担。所有工作流均以非阻塞方式触发或观察，绝不以历史成功替代当前 SHA 结果。


## 参考来源

1. [Swift Ubuntu 24.04 安装说明](https://swift.org/install/linux/ubuntu/24_04/)。
2. [DeepSeek Harness 锁定源码](https://github.com/deepseek-ai/deepseek-harness/tree/528c682e061696f5a160f363f236ecbf53cbd006)。
3. [SE-0371：Isolated synchronous deinit](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0371-isolated-synchronous-deinit.md)。
