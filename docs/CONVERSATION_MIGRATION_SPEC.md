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
