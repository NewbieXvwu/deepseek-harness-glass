# 原生会话根迁移规格记录

## 锁定来源

- 基线：`deepseek-ai/deepseek-harness@99f6f02fecdb7dff40c3fbc9470f5907c29f74ca`。
- 会话根：`packages/client/ui-conversation/src/client/skeleton/ConversationRoot.tsx`。
- 会话 header/body：`packages/client/ui-conversation/src/client/skeleton/ConversationSession.tsx`。
- 原生聊天快照归约蓝图：`packages/client/ui-conversation/src/client/conversation-nodes/chat-snapshot-builder.ts`。
- 真实 transcript 滚动行为：`packages/client/ui-conversation/src/client/chat/ChatView.tsx`。
- 可见文本：`packages/client/ui-conversation/src/client/locales.ts`。
- RPC：`packages/host/apiproxy/src/api/sessions.schema.ts`。
- SSE：`packages/host/apiproxy/src/api/events.ts`。
- 消息迁移形状：`packages/session/session-persistence/src/coordinator.ts`。

## 官方状态规则

| 规则 | 规格依据 | 原生映射 |
| --- | --- | --- |
| Composer 必须在无 session/session 切换间保持 mounted，禁用是属性而不是第二棵树。 | `ConversationRoot.tsx` 注释与 126–157 行。 | `NativeConversationColumn` 保持同一 composer root；后续阶段只切换 owner/disabled 状态。 |
| Hero 适用于无 session，或已打开且 blank 的 session；历史 replay 的 blank loading 处于 settling，避免 hero/docked 闪烁。 | `ConversationRoot.tsx` 68–82、169–193 行。 | `SessionStore.Phase` 分离 loading/ready/error；根 View 在保存现有欢迎态与 active transcript 间转换。 |
| Session header 对 blank session 隐藏，非 blank session 显示祖先路径和 view tabs。 | `ConversationSession.tsx` 61–129 行。 | 初版原生 history 只显示官方 Chat 标题；面包屑/tabs 在视图注册表迁移时扩展。 |
| `session.history` 返回连续 history events、`hasMore` 和可选 projections。 | `sessions.schema.ts` 238–242 行。 | 以 `SessionHistoryResponse` 加载初始历史；后续支持 prepend 型 load older。 |
| mux 重连后应重新打开 stream 并 refetch history；session frames 包括 durable `session/event`、订阅、queue、jobs、projection 与 stream error。 | `events.ts` 46–108 行。 | `NativeSessionStore` 使用 history 为权威基线，mux 只合并指定 session 的实时增量；错误保留在会话状态。 |
| `user/message` 当前 event 直接带 message identity/content，`assistant/message` 当前形状在 `data.message` 中携带 assistant content。 | `coordinator.ts` 470–501、537–555 行。 | transcript 首期只将 text content blocks 渲染为原生 user/assistant 气泡；tool/image/unknown blocks 被保留给明确 Tooling/Attachment adapters。 |
| `assistant/chunk` 的正式文本流分片是 `data.chunk.type === text-delta`，携带 index/text；历史可能有 sequence gaps，不能将 gap 当作数据丢失。 | `session-telemetry`，并由 `apiproxy` README/events 注释说明。 | 以 turn/step/index 键折叠 text delta，turn end 或 settlement 时关闭流式状态。 |

## 首期范围与延后项

首期会话根必须包含：历史加载、user/assistant text transcript、流式 assistant delta、loading/error、回到底部和 session 切换取消。工具行、图片附件、approval/question、queue、todo、stats、轨迹、交付物和未知 surface 不能假装已完整实现，分别迁移到后续 Tooling、Attachment 和插件适配阶段。

## 官方 ChatView 滚动行为（待原生收敛）

`ui-conversation/src/client/chat/ChatView.tsx` 规定以下行为：首次 history open 在没有已保存 reader position 时跳到底部；读取者在底部时只随新的 flow tip 或内容高度变化继续跟随；读取者离开底部后不得被被动 render/流式更新重新钉回底部；用户自己的新消息与 pending steering 消息强制可见；点击“Load earlier”前保存语义行和相对 top，prepend 后恢复该行位置；仅非底部时显示“Back to bottom”。

原生 SessionStore 已实现 Host `beforeSeq` 分页和 `hasMore`/loading state。下一次会话视图收敛将把 SwiftUI scroll geometry 的 reader ownership、prepend anchor 与 `chat.toBottom` 条件控件加入，不能以“每次 items 更新都 scrollTo bottom”的方式替代。

## 工具行与详情检查器规格（下一原生域）

- `ui-tool/tool/components/ToolRow.tsx`：工具行默认折叠；任一有 body/output/card material 的行可展开；运行/失败/停止通过 conversation locale `row.running`/`row.failed`/`row.stopped` 提供非颜色无障碍状态；详情面板是单一 call 的全高度阅读表面。
- `ui-tool/tool/models/tool-call-model.ts`：标准 generic fallback 按 `bash/read/search/write/edit/code/others` 分类，标题为官方 Figma literal（`Search`、`Read`、`Bash`、`Write`、`Edit`、`Code`、`Tool call`）；summary 从 call args 派生，result 文本由已 settled 的 result content blocks 展开。
- `ui-tool/tool/ToolCallTree.tsx`：选择状态按 `callId` 在树中共享，Inspect 将行路由到唯一详情列；nested subcalls 使用官方缩进连接线。
- `ui-tool/tool/ToolDetails.tsx`：详情优先选用声明 card 的 full-height renderer；generic running 显示 `details.running`，已 settled fallback 显示 flattened result；详情而非聊天行承担长输出阅读。

原生实现必须保留 event/view 的 merge-extensible 边界：只有已映射 generic text/JSON 与获准的 native card adapters 可显示；未知 card 不能被任意 HTML 或 WebView 自动渲染。
