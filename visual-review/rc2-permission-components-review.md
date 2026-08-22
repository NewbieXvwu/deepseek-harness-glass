# DeepSeek Harness 0.1.1-rc.2 权限组件视觉复核

**复核日期：** 2026-08-22
**锁定上游：** `deepseek-ai/deepseek-harness@b150a551b8d465e31e418e1b2eaf5e79bbb7d28e`（`dsh-v0.1.1-rc.2`）

> 本记录仅覆盖 `0.1.1-rc.1` 至 `0.1.1-rc.2` 发生可见语义变化的权限模式选择器、Full access 确认弹窗与设置页权限行。它不将 Linux 上的源码审阅替代为 macOS 原生截图验收；
> 权威配对截图、AX tree 和像素差异仍须由本分支的 `macos-26` 工作流产出。
> 
> 

## 上游变化与复核范围

| 受影响表面 | rc.2 上游行为 | 原生对齐措施 | 本地复核结果 |
|---|---|---|---|
| 会话输入栏权限选择器 | `danger-full-access` 固定显示为 **Full access**；其余选项保留 Host 名称，若为 kebab-case 则按 title case 显示。 | `PermissionPresetProjection.
display` 不再把 `read-only` 与 `workspace-write` 强行投影为产品固定名；
仅固定 Full access。 | 通过源码与回归预期复核。 |
| Full access 确认弹窗 | 英文名称在中文确认标题、说明和主操作中保持 `Full access`，不再翻译为“完全权限”。 | 从 rc.2 `OfficialLocaleCatalog` 重建可见文本；
`NativeFullAccessPermissionConfirmation` 继续只在 Full access 提升时显示确认与勾选门槛。
| 通过 locale provenance 门禁与运行时可见文本映射复核。 |
| 设置页 Permission 行 | 动态 Host 选项的标签不得被本地硬编码覆盖；非 machine-name 标签须原样显示。
| `NativeSettingsRoot` 继续使用 `PermissionPresetProjection` 的 Host-authoritative 选项；投影测试覆盖 `Workspace` 这类非 kebab-case Host 标签。
| 通过核心投影回归预期复核。 |

## 可见语义核对

| 观察项 | 锁定 rc.2 规格 | 原生实现 | 结论 |
|---|---|---|---|
| 标签顺序与选中值 | 由 Host schema 广告的 `defaultPreset` 选项决定。 | 原生仅对已广告的选项形成 mutation，未知值不会进入 transport。 | 一致。 |
| 普通标签的大小写 | `read-only` 显示为 `Read Only`；kebab-case 标签逐词 title case；已有空格或大写的 Host 标签保持原样。
| `display(value:suppliedLabel:)` 仅规范严格 ASCII kebab-case。 | 一致。
|
| Full access 标签 | 无论 Host 输入名为何，`danger-full-access` 显示为 `Full access`。 | `display` 对该值使用固定产品名。 | 一致。 |
| 风险确认 | 仅 Full access 升级显示确认，且确认前必须明确确认风险。 | `NativeFullAccessPermissionConfirmation` 保持该交互和禁用态。 | 一致。 |
| 中文确认文案 | 名称保持英文 `Full access`。 | 从 rc.2 官方 locale catalog 读取，而非原生硬编码翻译。 | 一致。 |

## 实际官方捕获

已在锁定 rc.
2 WebUI 中生成 [`permission-confirmation-light-official.
png`](official-b150a55/permission-confirmation-light-official.
png) 和同名 [ARIA/几何 JSON](official-b150a55/permission-confirmation-light-official.
json)。
捕获固定为 **1280×840、DPR 1、en-US、light**；
无 console warning 或 page error。
截图显示居中白色风险模态、背景遮罩、右上 Close 控件、红色警告图标、未勾选确认框、Cancel 与禁用的 Enable Full access 操作。
ARIA 同时确认背景的 `Access mode, current: Workspace Write` 在确认期间被禁用，以及对话框拥有精确的标题、Close、checkbox、Cancel 和 Enable Full access 可访问名称。

原生端现将确认状态提升到 `NativeActiveConversationSurface` 的全尺寸覆盖层，并以 `permission-confirmation-light` 快照模式重放相同的未勾选状态；
选择器仍仅根据 Host 广告的权限选项触发该确认。
该新场景已接入官方捕获、原生快照、差异报告和视觉策略。Linux 环境无法生成 macOS SwiftUI/WindowServer 图像，因此原生 PNG、AX tree 与成对差异报告由本分支 `macos-26` CI 作为权威证据产生。

## 复核依据

本地已通过 rc.
2 的 Official UI Spec、locale AST provenance、theme token、column-layout、RPC DTO、transport contract、总体 official-spec 门禁及 `test_visual_policy.
py`。新官方捕获测试仅执行该场景并通过。对本次受影响的标签规则，`PermissionPresetProjectionTests` 新增并更新了非 kebab-case Host 标签保留的断言。

官方实现参考：

1. [`PermissionSelect.tsx`](https://github.
   com/deepseek-ai/deepseek-harness/blob/b150a551b8d465e31e418e1b2eaf5e79bbb7d28e/packages/client/ui-conversation/src/client/skeleton/Permissio
   nSelect.tsx)
2. [`PermissionRow.tsx`](https://github.
   com/deepseek-ai/deepseek-harness/blob/b150a551b8d465e31e418e1b2eaf5e79bbb7d28e/packages/client/ui-permission-presets/src/PermissionRow.tsx)
3. [`locales.ts`](https://github.
   com/deepseek-ai/deepseek-harness/blob/b150a551b8d465e31e418e1b2eaf5e79bbb7d28e/packages/client/ui-conversation/src/client/locales.ts)

## macOS 权威视觉验收待办

提交拉取请求后，`macos-26` 工作流必须重建官方 WebUI 与原生应用，并保留本次分支的 `permission-confirmation-light` 官方 PNG、原生 PNG、ARIA、差异 PNG 与报告 JSON。
人工复核应在同一 1280×840 视口、相同语言和颜色模式下检查权限选择器、Full access 确认弹窗、设置页 Permission 行及其键盘焦点顺序。仅系统材质和平台字体光栅化可以按既有策略归类；标签、顺序、确认门槛、可访问名称和动态 Host 标签均不得出现差异。
