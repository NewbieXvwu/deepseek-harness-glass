# PR #5 新质量规定专项合规审计

**审计基线：** PR #5 已合并至 `main`（merge commit `806ad126ce737236ec574a8428f79e5722fbdee6`）。本审计依据 `docs/REVIEW_PROTOCOL.md` 新增的 **“验证运行态行为，严禁源码文本对暗号”**、**可证伪性与重构容忍度**、**生命周期韧性覆盖**、**工具自由** 四项规定完成。

> 结论：PR #5 已将三个最脆弱的 gate 缩减为较少的文本规则，但当前仓库仍存在多项 CI 脚本把本项目 `.swift` 源码作为文本、通过关键词、正则或字符串存在性决定通过/失败。因此，**存在既有违反项**；它们不能继续作为质量验收证据，须以运行态/编译产物/真实 UI 或协议行为测试替换，而不是仅改写关键字。

## 审计范围与发现

| 优先级 | 现有 gate | 违反方式 | 新规定下的替代验证 | 当前处置 |
|---|---|---|---|---|
| P0 | `check-no-webview.sh` | 对 App/Core/UI Swift 源码使用 `rg` 匹配 WebKit、DOM、JS、`PluginWebHost` 符号。 | 在 macOS UI integration test 启动 welcome/conversation/settings，并递归检查实际 `NSView` tree 无 `WKWebView`；Plugin sandbox 实现后只在独立 route 测试中允许一张受限 web host card。 | 待替换；同时满足 T11.7 的依赖隔离要求必须迁移为 SwiftPM graph + runtime host isolation 证据，不能复用源码 grep。 |
| P0 | `check-module-boundaries.py` | 枚举并读取各 target 的 Swift imports/禁用 API 文本。 | 以 `swift package describe --type json` 验证实际 target dependency graph；以独立 SwiftPM build、module import tests 和运行期 Host/UI integration 证明边界。 | 待替换；保留 target graph 验证但移除 source import text scan。 |
| P0 | `check-no-feature-transport.py` | 对 Feature/UI Swift 源码查找 transport/process/API 模式。 | XCTest 向 Feature 注入拒绝型 typed facade，断言所有 UI 行为经 facade 可观察调用；运行期测试确保 UI 无法自行启动 Host/进程。 | 待替换；须随 T4/T8 facade test expansion 交付。 |
| P1 | `check-official-locale-literals.py` 与 `check-official-spec.py` 的 UI literal regex | 通过 `Text("...")` 等源码正则判定文案来源。 | UI/accessibility tests 读取实际 rendered labels，并与 `OfficialLocaleCatalog`/官方 fixture 进行值比对；可见字符串由 view runtime 暴露而非源码文本。 | 待替换；PR #4 的 fail-closed lint 仍是既有违反项，不能再扩展。 |
| P1 | `check-glass-policy.py` | 虽移除 count/required strings，仍遍历 Swift source 检查 `.glassEffect(`。 | 启动真实窗口，在 Reduce Transparency/Contrast/Motion 矩阵中收集 window/view/material telemetry 与截图；断言正文/hero/composer 未出现 glass surface。 | PR #5 改后仍违规，待迁移。 |
| P1 | `check-native-structural-material.py` | 仍扫描 Swift source 是否包含 `NSVisualEffectView`。 | 原生窗口 integration test 验证 sidebar/inspector 实际使用系统 split-view material，且不存在 ad-hoc structural visual-effect view。 | PR #5 改后仍违规，待迁移。 |
| P1 | `check-accessibility-baseline.py` | 仍读取 Swift source path 是否存在。 | UI automation/VoiceOver test 以真实 accessibility tree 比较每个场景的 label、role、focus 与 keyboard path。 | PR #5 改后仅保留文件存在性检查；仍不应作为无障碍质量 gate。 |
| P2 | `check-official-locales.py`、`check-official-ui-spec-build.py`、`check-runtime-asset-inventory.py` 及相关 official catalog scripts | 从项目 Swift specification source 中匹配 generated constant 或 `@main` 文字。 | 将 build revision、catalog hash、target graph 作为构建产物/Swift runtime API 输出进行比较；用 XCTest/CLI JSON 读取实际可执行模块公开值。 | 待按规格生成管线拆分；官方外部源/catalog完整性检查仍可保留，但不得把本项目 Swift 源码当断言输入。 |
| P2 | `check-official-column-layout-fixtures.py`、`check-official-interaction-scenes.py`、`check-official-theme-tokens.py`、`check-official-rpc-dto-manifest.py`、`check-official-transport-contract.py`、`test-official-ui-spec-build.py`、`test_visual_policy.py` | 部分检查读取本项目源码或以 source-file 字符串作为 fixture 成功条件。 | 迁移为 structured generated JSON、Host replay、XCTest reducer snapshot、实际 screenshot/layout/accessibility 断言。 | 逐项复核并迁移；不能因低优先级而继续作为完成任务的唯一证据。 |

## 非违规或可保留的验证形态

**官方外部源、JSON Schema、锁定 Host payload、生成 catalog、截图/像素报告、SwiftPM 构建图与真实协议 replay** 的完整性验证本身不与新规定冲突，前提是测试的是结构化产物、运行时输出或真实交互，而不是匹配本项目 Swift 源的词汇、排版和出现次数。

同样，静态解析 **SwiftPM manifest 的结构化 `swift package describe --type json` 输出** 可作为 module dependency 的构建产物验证；它不是对 `.swift` 实现文本“对暗号”。未来 PluginWebHost 隔离必须将 T11.7 的约束表达为允许/禁止的 target graph 和实际 host view isolation 测试。

## 后续执行顺序

1. 首先替换 P0 三类 gate，以免任何后续 TODO 的 CI 继续将源码关键词匹配误作为质量证据。
2. 将 P1 visual/accessibility gate 改为真实 AppKit/SwiftUI UI automation、accessibility tree 与 WindowServer screenshot evidence。
3. 将 P2 generated spec/locale/transport gate 改为 build artifact JSON、Swift runtime API 和 Host replay evidence。
4. 每个迁移须保留至少一个**真实缺陷可令测试失败**的负例，且同等行为的重构不可造成失败；完成后删除旧 gate 的 workflow invocation，不能双轨永久保留文本扫描。

该审计将随每项迁移更新，不会把任何遗留 source-text gate 作为 TODO 完成、视觉 enforce 或安全通过的唯一依据。
