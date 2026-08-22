# GP-3：单 document 滚动标量同步

**状态：** 已建立纯 Core `GhostPlaneScrollSynchronizer`、原生 skeleton 内部内容层和 WebKit 参数化 transform 接口；有 Core XCTest、Linux Swift 6.2.4 回归与 `portable-checks` 接入。整体 GP-3 未完成，原因是 native `NSScrollView` 的 display-link coalescing、主界面实际调用、120Hz ProMotion 观测和跨插件真实互操作尚未形成 macOS 权威证据。

## 1. 来源与模型

官方 ChatView 以真实滚动容器的 `scrollTop` 为阅读位置真源，并在恢复、prepend 及 follow-to-bottom 时维护该位置；当内容增长而读者仍在底部时才随内容向下跟随，不能因 scroll-driven UI re-render 反复 snap 到底部。[1] Ghost Plane 不拥有官方聊天内容，也不应创建第二个会话滚动 authority；项目兼容提案据此规定所有固定锚点和滚动内容锚点位于一个主 document，而 native 会话流仅传递 `scrollOffset` 标量，由平面内部变换内容。[2]

`GhostPlaneScrollSynchronizer` 接受 `(documentEpoch, sequence, scrollOffset)`。epoch 必须等于当前 main document generation；sequence 必须严格大于本 epoch 已应用的最后样本；offset 必须为有限 `Double`。过期 epoch、重复/倒退 sequence 及 `NaN`/infinity 都不会改变 latest authority。保留 signed offset 使 AppKit 弹性 overscroll 不会在边界被人为截断；其唯一 renderer payload 是 `{ "scrollOffset": number }`，没有 CSS 或 JavaScript 字符串。

| 输入条件 | 同步器结果 | 平面效果 |
|---|---|---|
| 当前 epoch、严格更新 sequence、有限值 | `applied` | 允许宿主参数化调用。 |
| 旧 document epoch | `ignoredStaleEpoch` | 不移动新 document。 |
| 重复/倒退 sequence | `ignoredStaleSequence` | 不回滚或改写最新滚动 authority。 |
| NaN 或 infinity | `rejectedNonFiniteOffset` | 拒绝 CSS transform 参数。 |

## 2. skeleton 与 WebKit 边界

`GhostPlaneSkeleton` 增加唯一 `#ghost-scroll-content[data-ghost-scroll-content]`。它位于已有 `data-conversation-scroll` 内，包住 session/chat flow、turn tail、toolview 与 composer seat；header、三栏 root 和 scroll container 本身不随标量变化。已有官方 slot、anchor、geometry 与 selector inventory 保持不变。

`GhostPlaneWebViewHost.applyScrollOffset(_:)` 仅在 native skeleton 的 final URL 仍是 loopback root 后工作，通过 `callAsyncJavaScript(arguments:)` 传递数值。document-start 固定 bootstrap 再次要求 `typeof offset === 'number' && Number.isFinite(offset)`，仅对 `#ghost-scroll-content` 设置内建 `translate3d(0, -offset px, 0)` 和记录 `--ghost-scroll-offset`。这不是 plugin script 的 CSS/JS 注入通道，也没有将 event/selection/drag 或 loader capability 隐藏在 scroll API 中。

## 3. 验证边界

`GhostPlaneScrollScalarTests` 与 `glass/ci/ghost-plane-scroll-scalar-portable-check.swift` 覆盖单调应用、epoch/sequence 延迟回调隔离、signed elastic offset、非有限拒绝和 primitive payload。`GhostPlaneSkeletonTests`/其 Linux 回归锁定内部 transform anchor，`GhostPlaneWebViewHostTests` 在 macOS target 验证实际 DOM transform 与 offset custom property。

> 允许惯性时短暂一帧拖影属于提案允许的视觉瑕疵；**功能错位不属于**。在真实 `NSScrollView` → host 调用接入、120Hz 抓帧、锚点与插件跨服务运行证据完成前，GP-3 不得勾选。

## Swift 6 严格并发析构依据（2026-08-22）

macOS-26 `native-ui` run `32545688375` 显示普通 `deinit` 在 `@MainActor` class 中仍是 nonisolated，不能读取 `NSObjectProtocol` 或 `Timer` 等 non-Sendable stored state。依据 Swift Evolution **SE-0371 — Isolated synchronous deinit**，全局 actor 隔离类可使用 `isolated deinit`，让析构 body、isolated stored properties 的销毁及对象释放在相应 actor executor 上执行。因此 `GhostPlaneScrollViewBridge` 的 observer 注销和 timer invalidation 使用 `isolated deinit`：它只修复资源释放的隔离边界，不更改 scroll offset、source sequence 或 document epoch 的 authority 语义。

## References

[1]: https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/ui-conversation/src/client/chat/ChatView.tsx "Official ChatView scroll-position and follow behavior"

[2]: ../docs/PLUGIN_COMPATIBILITY_PROPOSAL.md "Ghost Plane proposal: one document and scrollOffset scalar"

[3]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0371-isolated-synchronous-deinit.md "SE-0371: Isolated synchronous deinit"
