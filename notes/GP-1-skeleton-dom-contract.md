# GP-1：Ghost Plane 骨架 DOM 合同

**状态：** 已实现纯 Core 骨架生成器、Core XCTest 与 Linux Swift 回归；该任务保持未勾选，直至当前提交的 macOS-26 Core 测试提供自身成功证据。

## 1. 官方结构来源

锁定官方 `ConversationRoot` 将 session header 置于 scrollport 外，把 `conversation.session` 与 `conversation.composer` 放入同一个 `[data-conversation-scroll]` 主体，并把 sticky composer 作为 `[data-composer-seat]`。[1] 官方 `ChatView` 在该 scrollport 中产生 `[data-chat-flow]`，且以 `[data-chat-anchor-key]` 找到稳定行、以 `data-streaming` 标记流式状态。[2]

官方 SlotMap 将 `conversation.session`、`conversation.session.header`、keyed `conversation.chat.node`、`conversation.chat.turnTail`、`conversation.details.tool` 与 `conversation.composer` 定义为结构性 seat；其中 session owner 明确要求 view ring 与 sticky composer 处于同一 scrollport。[3] 因而本项目的 skeleton 不以屏幕截图或随意 HTML 猜测结构，而显式生成这些 anchor/slot 的空节点。

| 官方契约 | GP-1 skeleton 表达 | 约束 |
|---|---|---|
| `[data-conversation-scroll]` | `ghost-conversation-scroll` | 唯一 session scrollport，含 flow 与 composer seat。 |
| `[data-chat-flow]` | `ghost-chat-flow` | 仅承载结构性行和 slot hole，不载入用户文本。 |
| `[data-chat-anchor-key]` / `[data-chat-flow-key]` | 每个 native-provided `ChatAnchor` | key 仅接受受限 ASCII identity 集；重复或不安全 key 在 HTML 生成前失败。 |
| `data-streaming` | 每个 anchor 为 `false` | skeleton 从不伪造或消费流内容。 |
| `conversation.chat.turnTail` | `ghost-turn-tail` | 锚点存在，内容为空。 |
| `tool.call.toolview` / `conversation.details.tool` | `ghost-toolview` / `ghost-details-tool` | 仅建立将来的插槽位置，不挂载 plugin renderer。 |

## 2. 原生权威与内容隔离

`GhostPlaneSkeletonInput` 只接受 native 侧已经拥有的 viewport、sidebar/details preference 和 stable chat anchor key。它调用现有 `OfficialColumnLayout.resolve` 取得三栏宽度，而不复制 CSS 公式；输出只含空元素、data attributes 与签名稳定的 ID map。不会写入 session 文本、模型输出、凭据、插件 HTML、JavaScript URL 或 runtime closure。

生成器按 fail-closed 规则拒绝非有限几何、重复 anchor 与不在 `[A-Za-z0-9_.:-]` 范围内的 anchor key。即使调用方绕过后续 T11.1/T11.4 admission，GP-1 也不会将不受控 key 直接插入 DOM 属性。`

> GP-1 不是 WebView host，也不是 module loader。WKWebView 生命周期、same-origin policy、bridge injection gate、SlotRegistry 激活与 tapIndex sanitization 仍由 GP-2 / T11.5 实现；GP-1 只提供 native-authoritative、内容为空的结构和映射表。

## 3. 验证资产

`GhostPlaneSkeletonTests` 验证 production generator 与 `OfficialColumnLayout` 一致、所需 scroll/chat/composer/slot anchor 存在、内容不进入 skeleton、重复和不安全 key 被拒绝。`glass/ci/ghost-plane-skeleton-portable-check.swift` 在 Linux Swift 6.2.4 以同一生产 source 验证 layout/contract/fail-closed 行为，并已加入 `portable-checks`。

## References

[1]: https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/ui-conversation/src/client/skeleton/ConversationRoot.tsx "Official ConversationRoot scroll and composer topology"
[2]: https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/ui-conversation/src/client/chat/ChatView.tsx "Official ChatView flow and anchor contract"
[3]: https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/ui-conversation/src/client/contract/slots.ts "Official conversation SlotMap contract"
