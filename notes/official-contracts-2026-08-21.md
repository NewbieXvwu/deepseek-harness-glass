# 本轮官方 Harness 契约摘录

## Agent Presets

来源：`/home/ubuntu/deepseek-harness-official/packages/client/ui-agent-preset/src/client/settings-store.ts` 与 `AgentPresetSeat.tsx`。

- 默认 preset 的持久化字段为 Settings namespace `agent-presets` 的 `default`；写入通过 settings update/mutate，成功后应从 Host authority 重读 roster。
- seat picker 仅服务于即将开始的 blank session；一旦 session 已非 blank，不能再交换 preset。
- picker 当前选择优先 session 的 Host composition；否则使用 Host roster 的 default；候选不得自造，broken preset 不可选择。

## Models / Provider Settings

来源：`/home/ubuntu/deepseek-harness-official/packages/client/ui-settings-models/src/client/store.ts` 与 `ProviderEditor.tsx`。

- provider directory 仅提供 route id、display name、settings namespace/path、active/declared 等 Host 元数据；未知 provider 不可由客户端推导编辑字段。
- 官方 provider editor 的 curated family 仅覆盖 deepseek 与 pi-ai；未知 layout 只展示 advanced hint。
- 非 secret profile edits 必须是最小 settings path operations、使用 namespace revision；credential 值走 write-only credential set。
- 已解析 profile 的 credential ref 来自该 profile 的 `apiKeyEnv`；仅在新 route 提交 key 时，官方约定 fallback 为 `PROVIDER_ID_API_KEY`。
- reasoning effort 是 per-model capability，不得创建 provider-scope selector。

## 安全边界

- Markdown 外链仅可为绝对 HTTP(S)，不得透传 file/data/javascript/relative destinations；进一步拒绝 userinfo 与端口 0。
- 诊断红线应清除 bearer、普通 key/value、URL userinfo 与 JSON 字符串中的 api_key/cookie/token/secret/password。

这些条目是后续实现的参考记录，不替代锁定官方源的再次核对。

## Models discovery candidate adoption

来源：`/home/ubuntu/deepseek-harness-official/packages/client/ui-settings-models/src/client/ModelListEditor.tsx` 与 `ProviderEditor.tsx`。

- Model discovery 返回后，已存在于 provider models 草稿的 candidate ID 初始不选中；仅未配置 ID 初始选中，避免 Host discovery 的默认元数据覆盖用户调优字段。
- 采纳只遍历最新 Host candidate 集合中被选择的 ID；伪造或已过期的 selected ID 绝不能进入 settings mutation。
- 新行只可采用 Host 实际披露的 `id`、`name`、`contextWindow`、`maxTokens`；同 ID 的既有草稿行及未知未来字段原样保留。
- Provider editor 把完整 models 数组写入 provider profile 的相对 `models` path，并使用当前 namespace revision；只有 Host accepted settings 回包成为新 authority。
- picker 文案来自 `ui-settings-models.fetchModels/fetchTitle/fetchEmpty/fetchSelectAll/fetchDeselectAll/fetchAdopt/cancel`；credential 文案来自 `keyInput/keyPlaceholder/keyStored/keyEnvLocked/apply/applying/remove`。

## Workspace event 与 reorder authority

来源：`/home/ubuntu/deepseek-harness-official/packages/client/connection/src/client/fixture.ts` 与 `packages/client/connection/tests/fixture.client.spec.ts`。

- `host/workspace-changed`、`host/workspace-removed`、`host/workspace-order-changed`、`host/archived-sessions-changed` 是 browser authority invalidation；native 不得把通知 payload 增量拼入树，必须重新获取完整 `workspace.list` 与 `session.list`。
- `workspace.insertBefore` 的 Host value 是 `workspaceIds`，`workspace.insertSessionBefore` 的 Host value 是 `workspace`；接受 receipt 不等于本地顺序 authority，浏览器只在后续完整 Host list refresh 后改变顺序。

## Permission high-risk confirmation

来源：当前锁定 RC8 `conversation.input.access` / `ui-conversation.access.confirm.*` 契约。

- 完整 session `permissions` projection 提供选项，`/permission <preset>` 是唯一写路径；`danger-full-access` 必须先经过 acknowledgement confirmation。
- confirmation 的 title、description、acknowledge、cancel、enable 必须来自 `ui-conversation.access.confirm.*`；确认后仍需等待 Host 下一份 permissions projection 才更新可见状态。

这些条目补充上文，不替代下一次实现前对锁定官方源的核对。

## Context meter projection

来源：`/home/ubuntu/deepseek-harness-official/packages/client/ui-conversation/src/client/skeleton/ContextMeter.tsx`、`chat/StatsLine.tsx` 与 `packages/llm/token-meter/src/projection.ts`。

- Context meter 读取 session `contextPressure` projection；仅当 usage 与 route `contextWindow` 均存在时显示，二者都是 informational Host facts，不能被 native 估算、计费或作为 prompt gating 输入。
- usage 分子优先 `projectedTokens`，仅在字段缺失时 fallback 到 `pressureTokens`；projected figure 结合 compacted surface 的变化，因此 compaction 发生后不必等待下一次 provider usage 回报。
- 百分比为 `round(usedTokens / contextWindow * 100)` 并上限 100。`contextWindow` 缺失时必须隐藏并关闭详情；capacity 与 pressure 来自独立 last-wins projection fields。
- 触发器/详情标题使用锁定 `ui-conversation.context.aria` 与 `context.used` locale；官方 breakdown 仅在 `contextBreakdown` projection 实际存在时才展示。
