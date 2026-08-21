# GP-4：事件桥合同与回环抑制

**状态：** 已完成纯 Core typed event contract、document epoch/sequence fence、有限 echo window、Core XCTest 和 Linux Swift 6.2.4 回归；尚未把 AppKit/WKWebView 平台对象连接到该合同，故 GP-4 保持未完成。

## 1. 官方来源与范围

官方 InputBar 接收完整 keyboard/paste 浏览器事件，而不是仅凭单个键值猜测提交；官方附件组件只把携带 `Files` 的 `DataTransfer` 视为图片 drop，并维护 drag enter/leave depth、`dropEffect` 和 `canAcceptDrop` 判断。[1] [2] 因此本桥不定义“某插件的快捷键表”，而以带 `key`、`code`、location、modifier、repeat、composition 和 down/up phase 的 `Keyboard` 语义转发，并将 image paste 与 drag 的实际文件所有权留在 native 安全入口。

`GhostPlaneBridgeEvent` 覆盖 keyboard、image paste、selection、drag 四类。选择投影只使用 native skeleton `ghost-*` element ID 与 anchor/focus offset，禁止 DOM `Range`、HTML、selector 或复制文本。粘贴/拖拽的 image event 仅携带 opaque `attachmentID`、显示名和 MIME；原始 bytes 不进入 plugin message，未来 AppKit adapter 必须先创建 Host-private temporary file，再调用已有 `NativeImageAttachmentAdmission` 读取 magic bytes、ImageIO dimensions、MIME 与 message limits。[3]

| 事件 | Core bridge 数据 | 明确禁止跨界 |
|---|---|---|
| Keyboard | phase、key、code、location、modifier、repeat、composition | 任意 JS callback/source、按插件特判。 |
| Image paste | opaque attachment ID、name、MIME | 原始 bytes、file path、跳过 image admission。 |
| Selection | skeleton node IDs 和 offsets、collapsed flag | DOM Range、HTML、selector、选中文本。 |
| Drag | phase、operation、attachment IDs、有限坐标 | live `DataTransfer`、file path、非有限坐标。 |

## 2. document authority 与回环抑制

`GhostPlaneEventBridgeFence` 在每个 main document epoch 下为 native outbound message 分配序列，并保留固定大小（默认 256）的 native echo identity 窗口。plane inbound 必须是同 epoch、`.planeToNative`、严格增长 page sequence 和安全 event；已知 `echoOfNativeSequence` 被抑制，未知 echo 直接拒绝。该策略防止 native selection/keyboard state 投影再次被页面观察并回写 native state，同时避免高频输入使 diagnostic identity 无界增长。

> 此阶段仅建立数据合同与 admission fence，不生成 synthetic `KeyboardEvent`、`ClipboardEvent`、`Selection` 或 `DataTransfer`。真实 WebKit message handler、AppKit responder 分诊、temporary file 生命周期、focus/z-order 协调和 native draft 回写属于后续 GP-4 适配器工作，不能由纯 Core 通过替代。

## 3. 验证

`GhostPlaneEventBridgeTests` 和 `glass/ci/ghost-plane-event-bridge-portable-check.swift` 覆盖 current/stale epoch、direction、重复 page sequence、有界 echo eviction/抑制、四类合法事件、unsafe skeleton selection 和 non-finite drag。可移植检查直接编译 production source，已接入 `portable-checks`。

## References

[1]: https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/ui-conversation/src/client/skeleton/InputBar.tsx "Official InputBar keyboard and ClipboardEvent handling"

[2]: https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/ui-attachment/src/client/ComposerAttachments.tsx "Official composer DataTransfer drag/drop behavior"

[3]: ../glass/Sources/Core/Session/NativeImageAttachmentAdmission.swift "Project image attachment admission boundary"
