# RC1 官方 UI 变更视觉审查

> **审查状态：已完成源码与运行态复审；macOS-26 原生配对截图待 CI 工件补齐。** 本记录不把未获得同条件原生 PNG 的场景误标记为像素验收通过。

本审查以官方标签 `dsh-v0.
1.
1-rc.
1` 对应的 `528c682e061696f5a160f363f236ecbf53cbd006` 为基线，与此前 RC8 提交 `141eb6fef83422698aef7a981029e843e8161534` 比较。
运行态检查使用 Node `24.19.0`、隔离 `DSH_HOME` 以及锁定的 `@deepseek-ai/dsh` / `@deepseek-ai/dsh-web-frontend` `0.1.1-rc.1` 载荷。

## 证据与范围

| 项目 | 证据或固定条件 |
|---|---|
| 官方规格 | `deepseek-ai/deepseek-harness@528c682e061696f5a160f363f236ecbf53cbd006`，tag `dsh-v0.1.1-rc.1` |
| 前序基线 | `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534`，tag `dsh-v0.1.0-rc.8` |
| 运行态证据 | 隔离 loopback 官方 WebUI 的欢迎态；观察记录见 `rc1-runtime-observations.md`，截图为 `welcome-runtime-light.png` |
| 源码审查输入 | `packages/client/ui-conversation`、`ui-primitives`、`ui-user-questions`、`ui-workspace`、`ui-subagent`、`ui-permission-presets` 的
RC8→RC1 差异 |
| 原生映射 | `NativeMarkdownRenderer.swift`、`NativeApprovalQuestionViews.swift`、`NativeConversationHeader.swift`、`WorkspaceBrowserView.
swift`、`PermissionPresetProjection.
swift` |

## 官方变更与原生审查结论

| 官方 RC1 变更 | 可见影响 | 原生审查与处理 | 结论 |
|---|---|---|---|
| 四列及以上 Markdown 表格获得 `md-table-wide` 宽表规则、全聊天宽度突破和可见横向滚动 | 比较型表格不再被消息列裁剪；小表继续随列宽换行 | `NativeMarkdownTablePresentation` 在四列阈值切换；
`NativeMarkdownTable` 对宽表保持自然列宽并使用水平滚动 | **已映射** |
| 问答自定义答案由单行输入升级为自动增长文本区，增长上限为六行 | 选项内自由文本支持多行；无选项答案区避免单行截断 | 选项内字段改为垂直 `TextField`，`lineLimit(1...6)`；独立答案区高度按 RC1 调整为 `64–144pt`，
并保留 Shift+Return 换行 | **已映射** |
| 当前空白会话在工作区及扁平列表中置顶 | 新建会话不会因时间排序或已存本地排序而落在列表中部 | 增加 `BlankSessionPromotion` 状态，
并通过纯函数 `orderPromotingBlankSession` 同步所属账户和扁平账户的前置顺序 | **已映射** |
| 子代理目录入口改为会话标题谱系组件，子代理标题采用紧凑层级 | 子代理会话在面包屑中应不同于普通父会话 | `NativeSessionHeaderPresentation.Breadcrumb` 增加 `isSubagent`，子代理标题使用官方规格的 `12pt` 字体；
既有目录 popover 保留其 Host 驱动树与键盘导航 | **已映射（目录交互沿用已有原生实现）** |
| 内置权限预设改用产品定义标签 | `workspace-write` 不应显示为旧的 Host 简称 `Workspace` | `PermissionPresetProjection` 固定 `Read Only`、`Workspace Write` 与 `Full
access`；
未知 Host 选项仍保持保守回退 | **已映射** |
| 缓存命中百分比、输入编辑范围和引用标记 identity 的实现变化 | 主要是统计文本精度、编辑正确性及装饰稳定性，不引入独立壳层几何 | 原生没有对应的 Web 受控文本区或同构统计节点；列为行为复核，不以无依据的视觉装饰替代 | **不适用的壳层视觉变更** |

## 运行态观察

官方 RC1 在初次启动时先显示 `Internal Testing Notice`，随后是可跳过的 API key 引导。
关闭引导后，欢迎态保持轻量三栏结构：左侧导航包含 New Session、Workspaces、搜索/视图/新增工作区控制与 Settings；
主区居中展示 `Into the Unknown`、`Preview`、工作区选择器、`Standard mode`、输入区和提交箭头。RC1 的前端源码差异不涉及该欢迎态的 CSS 或组件结构，因此该截图作为升级健康度参考而不是被修改区域的像素验收依据。

## 回归覆盖

| 行为 | 回归测试 |
|---|---|
| 空白会话置顶、去重和重复应用稳定性 | `WorkspaceBrowserOrderingTests.testBlankSessionPromotionMovesNewBlankToFrontAndIsIdempotent` |
| 四列表格进入宽表展示、三列内保留列内布局 | `NativeMarkdownRendererTests.testRC1WideTablePresentationStartsAtFourColumns` |
| 子代理面包屑具备显式层级语义 | `NativeConversationHeaderTests.testSubagentAncestryAndBlankHeaderVisibilityMirrorRC8Rules` |
| RC1 工作区写入权限标签 | `PermissionPresetProjectionTests.testProjectsDynamicHostPresetOptionsAndAdvertisedMutationOnly` |

## 配对验收待办

本地 Linux 环境已验证锁定的 `dsh web` 载荷可启动并完成 Host RPC fixture 捕获，但从官方源树构建完整 WebUI 时，
官方根构建在 `vendor/hmr` 的 TypeScript `exactOptionalPropertyTypes` 错误处失败，因而无法在此环境生成全套 Playwright fixture 截图。


该问题没有被作为原生像素一致性结论处理。合并前仍须由 `macos-26` 工作流生成同一 `528c682e` 的官方 PNG/ARIA、原生 PNG/ARIA、差异图及每项偏差分类；这一要求遵循 `docs/REVIEW_PROTOCOL.md` 的视觉与无障碍门禁。

> 本次结论仅确认所有**官方修改过且映射到原生表面**的区域都已重新审查，并已对 Markdown 宽表、问答输入、空白会话排序、子代理标题层级和权限标签实施最小同步。最终像素验收仍以 macOS-26 配对工件为准。
