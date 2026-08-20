# PR #5 新质量规定专项合规审计

**审计基线：** PR #5 已合并至 `main`（merge commit `806ad126ce737236ec574a8428f79e5722fbdee6`）。本审计依据 `docs/REVIEW_PROTOCOL.md` 新增的 **“验证运行态行为，严禁源码文本对暗号”**、**可证伪性与重构容忍度**、**生命周期韧性覆盖**、**工具自由** 四项规定完成。

> 结论：PR #5 已将三个最脆弱的 gate 缩减为较少的文本规则，但当前仓库仍存在多项 CI 脚本把本项目 `.swift` 源码作为文本、通过关键词、正则或字符串存在性决定通过/失败。因此，**存在既有违反项**；它们不能继续作为质量验收证据，须以运行态/编译产物/真实 UI 或协议行为测试替换，而不是仅改写关键字。

## 审计范围与发现

| 优先级 | 现有 gate | 违反方式 | 新规定下的替代验证 | 当前处置 |
|---|---|---|---|---|
| P0 | `check-no-webview.sh` | 原对 App/Core/UI Swift 源码使用 `rg` 匹配 WebKit、DOM、JS、`PluginWebHost` 符号，现已删除。 | `NativeWebViewIsolationRuntimeTests` 在 macOS XCTest 实际启动 sidebar、conversation、details 三个核心原生表面，递归检查 `NSView` tree 无 `WKWebView`；测试以真实注入 `WKWebView` 的负例证明探测器可证伪。Plugin sandbox 实现后仅在独立 route 测试中允许受限 web host card。 | **已闭环：`df057b6` macOS-26 [run 32343282886](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32343282886) ✅**；T11.7 仍须以 SwiftPM graph + runtime host isolation 证明 PluginWebHost 隔离，不能复用源码 grep。 |
| P0 | `check-module-boundaries.py` | 原枚举并读取各 target 的 Swift imports/禁用 API 文本，现已删除。 | `check-package-target-graph.py` 从 `swift package describe --type json` 验证实际 target path/精确内部依赖；`test-package-target-graph.py` 以非法 `GlassCore → GlassUI` 反向边和错误路径负例证伪。独立 SwiftPM build、module import tests 和运行期 Host/UI integration 将继续证明 API 职责边界。 | **已闭环：`7e115b2` macOS-26 [run 32343097874](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32343097874) ✅**；运行态 module/API 隔离覆盖仍随 T12.8 继续补齐。 |
| P0 | `check-no-feature-transport.py` | 原对 Feature/UI Swift 源码查找 transport/process/API 模式，现已删除。 | `NativeSessionAPI` 是 `NativeSessionStore` 的 typed domain-intent seam，生产 `SessionsAPI` 提供实现；`NativeSessionStoreTests` 注入拒绝型 recording facade，断言 composer prompt 真实抵达 facade、保持 typed content、拒绝后 draft 可重试。其余 workspace/settings action 随对应 UI 任务在同一注入模式补齐。 | **已闭环：`973644f` macOS-26 [run 32344399514](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32344399514) ✅**；不得恢复源码模式扫描。 |
| P1 | `check-official-locale-literals.py` | 原通过 `Text("...")` 等源码正则判定 UI 文案，现已删除。 | `NativeAccessibilityRuntimeTests` 在 CI 以 production `OfficialLocaleCatalog.values` 对 Composer labels 作 runtime 正例和动态 constructed non-official label 负例；同一文件保留实际 mounted native accessibility-tree 断言，须在具 TCC accessibility trust 的 GUI host 执行。 | **已完成 source-gate 删除与 CI runtime catalog 迁移；GUI accessibility-tree automation 仍待 T12.8 完整闭环**；不得恢复源码 literal regex。`check-official-spec.py` 的其他源码文本规则仍独立审计/迁移。 |
| P1 | `check-glass-policy.py` | 原遍历 Swift source 检查 `.glassEffect(`，现已删除。 | 实际 `approvedGlassEffect` 使用生产 `NativeGlassEffectDecision.materializes(policy:isEnabled:)`；`GlassPolicyTests` 以 enabled approved control 正例和 content/system-navigation/reserved-overlay/disabled 负例验证真实 materialization 分支，且保留 accessibility/motion/budget runtime cases。 | **已完成 source-gate 删除与 production decision 测试迁移，待当前提交 macOS CI**；Reduce Transparency/Contrast/Motion 的 WindowServer screenshot/telemetry matrix 仍待 T12.8 补齐。 |
| P1 | `check-native-structural-material.py` | 原扫描 Swift source 是否包含 `NSVisualEffectView`，现已删除。 | `NativeMaterialIsolationRuntimeTests` 实际装载 Conversation content surface，递归检查 runtime `NSView` tree 无 ad-hoc `NSVisualEffectView`，并以注入真实 effect view 的负例证明确实可检测；完整 shell 将继续验证系统 sidebar/inspector split material。 | **已完成基础实现迁移，待当前提交 macOS CI**；不得恢复源码 symbol 扫描。 |
| P1 | `check-accessibility-baseline.py` | 原按 fixture 读取 Swift source path 是否存在，现已删除。 | `OfficialAccessibilityBaselineCatalog` 从实际 GlassSpec resource bundle decode baseline；`OfficialUISpecBuildTests` 验证 RC8 commit、六条 scene、环境 contract、runtime official label resolution 与 unknown scene/unregistered label 负例。受 TCC trust 的 GUI host 继续运行真实 accessibility-tree/keyboard tests。 | 首次迁移 `601e095` 在直接 Swiftc app assembly 因 `Bundle.module` 不存在失败；loader 已改为既有 Package/main fallback，**待修复提交自身 CI**。GUI accessibility automation 仍待 T12.8 闭环；不得恢复 source path 检查。 |
| P2 | `check-official-locales.py`、`check-official-ui-spec-build.py`、`check-runtime-asset-inventory.py` 及相关 official catalog scripts | 曾从项目 Swift specification source 中匹配 generated constant 或 `@main` 文字。 | `check-official-locales.py` 已迁移为官方外部源→`official-locales.json` 的结构化 provenance/regeneration check；`OfficialLocaleRuntimeCatalog` 从 packaged JSON decode，`OfficialUISpecBuildTests` 对已编译 public `OfficialUISpec.LocaleCatalog` 验证 commit/revision、双语参数/plural 对称与完整 value map。其余 scripts 将把 build revision、catalog hash、target graph 作为构建产物/Swift runtime API 输出比较。 | locale 项已实现、待当前 CI；其余项待按规格生成管线拆分。官方外部源/catalog完整性检查仍可保留，但不得把本项目 Swift 源码当断言输入。 |
| P2 | `check-official-column-layout-fixtures.py`、`check-official-interaction-scenes.py`、`check-official-theme-tokens.py`、`check-official-rpc-dto-manifest.py`、`check-official-transport-contract.py`、`test-official-ui-spec-build.py`、`test_visual_policy.py` | 部分检查读取本项目源码或以 source-file 字符串作为 fixture 成功条件。 | 迁移为 structured generated JSON、Host replay、XCTest reducer snapshot、实际 screenshot/layout/accessibility 断言。 | 逐项复核并迁移；不能因低优先级而继续作为完成任务的唯一证据。 |

## 非违规或可保留的验证形态

**官方外部源、JSON Schema、锁定 Host payload、生成 catalog、截图/像素报告、SwiftPM 构建图与真实协议 replay** 的完整性验证本身不与新规定冲突，前提是测试的是结构化产物、运行时输出或真实交互，而不是匹配本项目 Swift 源的词汇、排版和出现次数。

同样，静态解析 **SwiftPM manifest 的结构化 `swift package describe --type json` 输出** 可作为 module dependency 的构建产物验证；它不是对 `.swift` 实现文本“对暗号”。未来 PluginWebHost 隔离必须将 T11.7 的约束表达为允许/禁止的 target graph 和实际 host view isolation 测试。

## 后续执行顺序

1. 三项 P0 gate（module graph、D0 WebView、feature transport）均已完成迁移并取得各自 macOS-26 成功 run；接着按 P1 顺序迁移 visual/accessibility source-text gate，以免任何后续 TODO 的 CI 继续将源码关键词匹配误作为质量证据。
2. 将 P1 visual/accessibility gate 改为真实 AppKit/SwiftUI UI automation、accessibility tree 与 WindowServer screenshot evidence。
3. 将 P2 generated spec/locale/transport gate 改为 build artifact JSON、Swift runtime API 和 Host replay evidence。
4. 每个迁移须保留至少一个**真实缺陷可令测试失败**的负例，且同等行为的重构不可造成失败；完成后删除旧 gate 的 workflow invocation，不能双轨永久保留文本扫描。

该审计将随每项迁移更新，不会把任何遗留 source-text gate 作为 TODO 完成、视觉 enforce 或安全通过的唯一依据。
