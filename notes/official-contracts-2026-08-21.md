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
