# DeepSeek Harness Glass 代码审查报告

审查范围：全部 149 个 Swift 源文件 + 91 个测试文件 + 48 个 Python 脚本 + 26 个 portable-check + 5 个 CI workflow + 装配脚本（合计约 380 个文件，5 万行）。
方法：27 路并行审计 agent（按模块/类别扇出，全部带原文证据与行号）+ 对高危发现的人工逐条复核。⭐ 标记为本人直接读过源码/编译验证过的铁证。

---

## 类别 1｜无意义测试 / 形式主义（最严重）

### ⭐ 仓库里躺着一个必然失败的测试
**`glass/Tests/Spec/OfficialUISpecBuildTests.swift:15`**

```swift
XCTAssertEqual(OfficialUISpec.sidebarBuildRevision, "528c682e")
```
而 `OfficialUISpec.swift:11` 定义 `sidebarBuildRevision = String(Build.sourceCommit.prefix(7))`，当前 `sourceCommit` 是 `b150a551...`（`official-ui-spec-build.json` 确认），即实际值 **"b150a55" ≠ "528c682e"**。这个测试在当前基线下**必然失败**，`native-ui.yml` 第 296 行 `swift test` 全量跑它。属于升级后无人维护的失修测试。

### ⭐ mirror-testing：测自己而非行为
- **`OfficialGhostPlaneContractTests.swift:8-18`**：`load()` 返回前已在 `OfficialGhostPlaneContract.swift:56-68` 逐字段 guard，测试再逐条断言这些值——恒真。例如 schemaVersion、moduleLoader 全部字段。
- **`GhostPlaneSkeletonTests.swift:58-76`**：把 `requiredSelectors` 静态常量数组 15 个字面量原样抄进测试比对；`:18-23` 调一遍生产 `OfficialColumnLayout.resolve` 再断言 `skeleton.layout == 该返回值`；`:36` 断言输入的锚点里不存在从未出现过的字符串 `"user authored content"`（测幽灵字面量）。
- **`RPCModelsTests.swift:69-72`**：`XCTAssertEqual(requestEnvelope, .clientRequest(request))`——断言刚赋值的变量等于其构造式。
- **`ci/official-ghost-plane-contract-portable-check.swift:29-37`**：用待测的 `GhostPlaneSkeleton.requiredSelectors` 原地填充预期 fixture 再验证比较（A==A，永远绿，防不了漂移）。
- **`NativeSettingsStoreTests.swift:173-178`**、**`NativeBuiltinPluginCardCatalogTests.swift:40-54`**、**`NativeModelDirectoryFailurePresentationTests.swift:8-20`**：测试把实现里 `LocaleCatalog.value(namespace:key:)` 的调用原样抄在断言右侧。
- **`ci/test-package-target-graph.py:20-31`**：用被测模块内部 `EXPECTED` 常量构造 baseline 再喂给自己写的 `validate()`——自证。

### 只验元数据/字面量，不验行为
- **`NativeAccessibilityRuntimeTests.swift:218-276`** 三个测试只做 `Set(官方字典).contains(硬编码常量)` 仪式检查，没有挂载任何 View。
- **`NativeSessionStoreTests.swift`** 约 10 个用例只调用 Preview 假数据方法（`loadSnapshot*Fixture`）并断言写死字段。
- **`NativeTodoDockTests.swift:23`** `XCTAssertTrue(NativeTodoDockPresentation.startsCollapsed)`（static let 恒真）；**`NativeTranscriptTailPresentationTests.swift`** 对 `{ isRunning }` 恒等函数断言。
- **`ci/check-runtime-asset-inventory.py:89-91`** 只查 JSON 字段非空，从不验证 `source/destination` 指向的文件真实存在；**`ci/check-official-interaction-scenes.py:43-45`** 只对 `apps/` 前缀做存在性检查，其余路径静默跳过。

### ⭐ API 误用导致"测试必然全挂"却无人发现
**`glass/Tests/PluginPlane/GhostPlaneWebViewHostTests.swift:66-85`**（生产代码 `GhostPlaneWebViewHost.swift` 同款写法）：

```swift
let result = try await host.webView.callAsyncJavaScript("...", arguments: [:], in: nil, in: .page) as? [String: Any]
```
我用本机 swiftc 6.2 实测该调用形态：编译警告 `constant 'result' inferred to have type '()'` + `no calls to throwing functions occur within 'try'`——**被解析为丢弃结果的同步重载**，`await` 不生效，`as? [String: Any]` 恒败，后续 6 条断言全部失效（从未真正校验任何 JS 返回值）。同样写法出现在生产 `applyTapIndex`/`applyScrollOffset` 中，意味着它们在 fire-and-forget 执行 JS 后立即返回。

### portable-check 双轨：同一逻辑的第三份拷贝
26 个 `glass/ci/*-portable-check.swift` 与 `Tests/Core` 的 GhostPlane* XCTest 几乎 100% 逐行重复，且为单文件编译各自复制粘贴 stub（`native-schema-form-draft-portable-check.swift:11-49` 手写分叉 DTO 已与生产漂移：`revision Int?` vs `Int`；至少 5 个文件硬编码 `OfficialUISpec.Build` b150a55 → 升级盲区）。`ghost-plane-skeleton-portable-check.swift:3-30` 自嵌一个缺少生产 `sidebarMinimum: 264` clamp 的简化 `OfficialColumnLayout`——**在验证一套与生产冲突的假规则**（240 宽在生产会被钳到 264 导致断言失败）。

### 形式主义"门禁"
- **`.github/workflows/documentation-integrity.yml:65-74`**：名为 Verify artifacts exist，实际 `if [[ -d ]]` 只 echo，不 exit 1。
- **`tools/review-deliverables-artifacts.sh:42-46`**：printf 打印 4 项需求清单，没有任何校验。
- **`release.yml:65-72` / `repair-backend.sh:41-50`**：冒烟只 `kill -0` 查进程活着（只测不崩溃），grep 到空 URL 也算 OK。
- **`ci/test_rc8_recapture_matrix.py:25-42`**：6 个场景共用同一个模板字面量 `` `${kind}-${colorScheme}` ``，只要模板出现过一次，任何场景被删都恒真通过。
- **`ci/test-ci-workflow-layout.py`**：断言 step 的人类可读 name 文案 + Package.swift 12 空格缩进字符串（改格式就假阳性、真的引入依赖却可能放行）。

---

## 类别 2｜过度防御 / 静默吞错（损害用户体验）

| 位置 | 问题 |
|---|---|
| `Core/Session/NativeSessionStore.swift:1523-1535, 1828-1843, 1803-1815` | **提示词发送失败、历史翻页失败、取消/中断子代理**全部空 catch 或 `try?`——用户发送失败无任何反馈，取消是否送达不可知 |
| `Core/Host/HarnessHostController.swift:455-468` | `writeLog` 连续 4 个 `try?`（打开/seek/write/原子写），磁盘满或句柄失效时**排障日志静默丢失** |
| `Core/Host/HostBuildVerifier.swift:98-104` | `try?` 把「文件损坏/权限受限/解析失败」全部折叠成 nil → 用户只看到模糊的 "does not match" |
| `Core/Transport/SSEClient.swift` | WebSocket 帧 JSON 解码失败 `try?` 后 continue 丢弃，无诊断 |
| `UI/Shell/NativeSplitContainer.swift:582-607, 640-650` | forkSession / archiveSession / addWorkspace 空 catch——**用户操作无声失效** |
| `UI/Workspace/WorkspaceBrowserView.swift:894-902` | 拖拽重排先乐观更新本地顺序，RPC 失败空 catch 且**不回滚**，本地与服务端脱节 |
| `UI/Settings/NativeAgentPresetStore.swift:69-79` | read/copy/remove 一律 `catch { return false }`，根因全丢 |
| `UI/Settings/NativeCredentialStore.swift:29-33` | 凭据刷新失败空 catch；`:28` `views = response.credentials.filter{...}` **整表覆盖，把其他卡片的已加载凭据视图抹掉**（高危状态缺陷） |
| `UI/Settings/NativeSettingsStore.swift:136-138` | `guard let draft... else { return }` 静默返回，调用方误判保存成功 |
| `Core/Plugin/NativeUIManifest.swift:184-192` | catch 不可能抛出的通用错误，伪装成 `integrityNotVerified` |
| `Core/Host/HostLifecyclePresentation.swift:27-28` | **`.ready` 状态 title 仍用 loading 文案** + `permitsInteraction: true`，UI 上"已就绪"却显示"正在加载" |
| `Snapshot/SnapshotExporter.swift:279-288, 366-371` | ScreenCaptureKit 与 screencapture 进程错误全 `try?`/空 catch |
| `Spec/OfficialAccessibilityBaseline.swift:31-35` | `try?` 吞掉具体 DecodingError |

---

## 类别 3｜脆弱手写实现 / 性能低下

### ⭐ 死代码 / 逻辑缺陷
**`glass/Sources/PortableCore/HostPathDisplay.swift:18`**
```swift
let normalizedPath = path.hasPrefix("/") ? path : path
```
三元两分支相同（原意应为 `"/" + path`），相对路径前缀正规化失效；`:32-36` 还用 `Array(value.unicodeScalars)` 全量拷贝 + ASCII 魔数 58/47/92 判盘符。

### 手写脆弱实现（有成熟方案不用）
- **`UI/Conversation/NativeMarkdownRenderer.swift`**：`:203-258` 手写 11 语言字符级高亮状态机（不支持多行注释/模板串）；`:260-272` reduce 拼接 SwiftUI.Text 造成 **O(N²)**；`:76` `try? AttributedString(markdown:)` 吞错；`:13-20,38-55` 正则清洗（见类别 4）。
- **`Core/Plugin/GhostPlaneBridgeWireEncoder.swift:27-66`**：22 个可选字段的巨型扁平 struct，每个 case 手写十几个字段赋 nil；`GhostPlaneBridgeWireDecoder.swift:19-48` 对应手写超长 guard 链。
- **`Core/Transport/SessionLogExporter.swift:113-128`**：手写 `Content-Disposition` 分号切分——**文件名引号内含分号会被截断**。
- **`Core/Transport/RPCModels.swift:105-120`**：错误码用 `contains("rate"/"busy")` 子串猜 disposition，`generate_failed` 等误判为可重试。
- **`tools/extract_brand_wordmark.sh` / `tools/extract_fish_logo.sh`**：`sed -n '24,53p'` **硬编码行号**从 TSX 切片 SVG——上游增删一行就静默产出残缺 SVG（同目录已有 AST 方案 `extract_official_icon_ast.mjs`）。
- **`tools/module-boundaries/add_package_imports.py:25-30`**：按行扫描往 Swift 文件插 import，文件开头有注释时会插进注释块内。
- **`Core/Host/HostDiagnostics.swift:126-127, 71-73`**：5 条正则链式全量替换脱敏 + 构造 summary 字符串再 `components(separatedBy: " -> ")` 反查状态名。

### 热路径性能问题
- **`NativeSessionStore.swift:3289-3292`**：live SSE 流每一帧 `JSONValue → JSONEncoder → Data → JSONDecoder → DTO` 双编解码（SSE 数据到达即该路径）。
- **`DSHAPIClient.swift:30-44`**：RPC 热路径 `Encodable→Data→JSONValue→Data→Response` 三重编解码往返。
- **`NativeToolViews.swift:115-126,198-203`**：Tool 行每次 body 渲染对同一参数字符串做 2 次 `JSONSerialization`。
- **`WorkspaceBrowserView.swift:538-603`**：搜索时 `matchingSessions` 与 `matchingHasMore` 各自独立重算全量合并/排序/去重（一遍渲染算两遍）。
- **`NativeSplitContainer.swift:699-771`**：粗粒度 `objectWillChange` 监听，任何状态变动全量重建三栏视图树 + `applyLayout(force: true)`。
- **`GhostPlaneSkeleton.swift:185-200`**：`elementSuffix` 每字符 `String(scalar)→Character` 再 reduce；`escape` 4 次全量 `replacingOccurrences`（且漏转义单引号）。
- **`ConversationNodeReducer.swift:392-406, 151-158`**：每次节点 start 全量 map+sort 所有 context（O(N·M log M)）；`locationData(scope:turn:step:)` 对字典 values 线性全表扫描——key 已含这些维度。
- **`OfficialAccessibilityBaseline.swift:60-62`**：1300+ 条字典每次调用 `values.contains` O(n)。
- **`NativeStatsDock.swift:31-34`**：硬编码 en + 手写循环 `replacingOccurrences` 做模板替换。
- **`check-official-spec.py:96-102`**：遍历每个图标都 subprocess 调一次 Python，里面再 spawn Node——循环内嵌套进程。
- **测试侧**：`RawEventReplayReducerTests.swift:254-256` 4000 事件逐个 new JSONEncoder/Decoder；`NativeSessionStoreTests.swift` 111 处 `Task.sleep(10ms)` 忙轮询；`SessionHistoryPagerTests.swift` 私有重写一个已知有单槽 continuation 覆盖泄漏缺陷的 AsyncGate（target 内已有 RecoveryGate）。

### 复制粘贴不复用
- `WorkspaceBrowserView.swift:1499-1531` NativeSessionStatusDot 逐字复制 NativeStateDot 点阵实现；`NativePluginCardDraft.swift:160-171` 与 `NativeSchemaFormDraft.swift:195-206` 整段重复的 JSONValue 路径扩展。

---

## 类别 4｜正则滥用（该用 AST 的用了正则）

| 位置 | 问题 | 正解 |
|---|---|---|
| `tools/spec-generation/generate_ghost_plane_contract.py:20,38-41,53-54` | **SLOT_RE 多行正则解析 TS 对象/类型**；DATA_RE 对拼接后的 TSX 全文扫 `data-*`（会误匹配注释/字符串） | 同目录已有 TS AST 标准，迁移到 TypeScript Compiler API |
| `Core/Plugin/GhostPlaneContentSecurityPolicy.swift:14-21` | 正则 `<(head)(?:\s[^>]*)?>` 匹配并切分 HTML 注入 meta（`<!-- <head> -->` 会被误中） | skeleton 生成时直接拼进模板 |
| `UI/Conversation/NativeMarkdownRenderer.swift:13-20,38-55` | 正则清洗 HTML/Markdown 预处理，**破坏行内代码等合法文本**；`(?is)<(script\|style\|...)[^>]*>.*?</\1>` 有回溯风险 | swift-markdown AST / MarkupVisitor |
| `Core/Host/HostDiagnostics.swift:126` | 正则解析 JSON 字符串值（`\"(?:\\\\.|[^\"])*\"`），嵌套转义失真 | 基于键值解析 |
| `tools/check-markdown-links.py:11` | 正则抓 Markdown 链接，代码块内伪链接误报、嵌套括号漏报 | Markdown AST |
| `tools/spec-generation/generate_official_transport_contract_manifest.py:50-53` | `symbol not in text` 子串搜索当"符号存在性"，注释/同名变量都会误判 | TS AST export 声明检查 |

---

## 总体判断

- 四类问题**全部存在且数量可观**，最刺眼的三处：① 一个必然失败的测试躺在库里没人理（`528c682e`）；② `HostPathDisplay` 三元恒等死代码；③ `callAsyncJavaScript` API 误用导致生产 fire-and-forget、测试断言全挂却不自知。
- 模式上高度集中：**"官方一致性"崇拜催生了 mirror-testing 与元数据仪式**（类别 1 大头）；**异步 RPC 全链路空 catch**（类别 2 大头）；**为单文件编译/可移植性反复复制 stub 与手写解析**（类别 3、4 大头）。
- 修复优先级建议：P0 修 ①②③（必红测试、死代码、await 失效）+ `NativeCredentialStore` 全表覆盖；P1 把 portable-check 并入统一 SwiftPM 测试目标（删 26 份重复 + 硬编码 stub）；P1 全仓库静默 catch 改为记录错误并反馈 UI；P2 spec 提取全面迁移 TS AST；顺手删除镜像测试（每删一条先确认其断言确为恒真）。

遗留未验证项：`callAsyncJavaScript` 在 macOS 26 runner 上的**运行时**行为（我验证的是编译期解析为重载为同步 Void）；`HostLifecyclePresentation` `.ready` 用 loading 文案是否为产品有意为之（从代码看是文案错配）。
---

# 清理处置记录（2026-08-22）

> 后续：用户要求"彻底清理，包括擦边"。本记录按类别逐项列出处置方式与验证结果。

## 一、无意义测试 / 形式主义（已全部清理）

| 处置 | 内容 |
|---|---|
| 删除 | `OfficialUISpecBuildTests` 自同构断言与必红 `528c682e`，镜像的 `testOfficialColumnLayoutExposesLockedComputeColumnsConstants` 等方法（fixture 驱动/catalog/theme/baseline 断言保留） |
| 删除 | `OfficialGhostPlaneContractTests` 8 条 load()-guard 恒真断言 |
| 删除 | `GhostPlaneSkeletonTests` requiredSelectors 镜像方法、幽灵字符串断言；布局断言改为真实 clamp 期望值 264/696/320 |
| 删除 | `RPCModelsTests` 自等断言、`GhostPlaneScrollScalarTests` 冗余键断言 |
| 删除 | `NativeAccessibilityRuntimeTests` 约 30 条字典 contains 仪式断言（负控制与真实属性断言保留） |
| 删除 | `NativeTranscriptTail/TodoDock/SplitLayout` 恒等函数与 static let 字面量断言 |
| 删除 | `NativeModelDirectoryFailure/SettingsStore/BuiltinPluginCard` 镜像方法；`WebViewIsolation` helper 自测方法 |
| 删除 | `NativeSessionStoreTests` 10 个 loadSnapshot* fixture 假数据用例（真实 applyMuxFrame 用例保留） |
| 删除 | `NativeUIManifestTests` 元数据仪式方法 |
| 删除 | **27 个 portable-check.swift 双轨全部删除** + `portable-checks.yml` 的 `portable-swift` job 移除（stub 与生产分叉、与 XCTest 重复、假布局 mock 均因此消失）；Python spec 门禁 job 保留 |
| 删除 | `test-package-target-graph.py` mirror 自证 → 静态 JSON fixture；`check-package-target-graph.py` 冗余二次检查 |
| 修复 | `test_rc8_recapture_matrix.py` 6 场景共用模板字面量 → 特有标识符 |
| 修复 | `test-ci-workflow-layout.py` 删 step name 文案断言 + 空格缩进断言（保留真实拓扑） |
| 修复 | `test-runtime-asset-inventory.py` 补核心规则 6 组变异用例 |
| 修复 | **`check-test-integrity.py`（新增）**：恒真断言扫描器接入 `portable-checks.yml`（report-only），全仓库重扫 0 命中 |

## 二、形式主义 gate / 只跑不验（已修复）

- `documentation-integrity.yml` visual-review 步骤：echo → 真实遍历校验 + exit 1
- `review-deliverables-artifacts.sh`：printf 清单 → 4 类交付物逐项存在性校验 + exit 1
- `release.yml` / `repair-backend.sh`：`kill -0` → 轮询提取 `http://127.0.0.1:<port>` + curl 探活，失败 exit 1
- `check-runtime-asset-inventory.py`：只查字段非空 → 增加 source/destination 文件存在性校验
- `check-official-interaction-scenes.py`：apps/ 白名单 → 按前缀解析到对应根逐项 is_file，未知前缀报错

## 三、静默吞错 / 过度防御（已修复）

- `HarnessHostController.writeLog`：4 个 try? → do-catch + 诊断记录 + stderr
- `HostBuildVerifier.packageVersion`：try? → do-catch + stderr
- `SSEClient` 帧解码：try? → do-catch + stderr
- `SnapshotExporter`：ScreenCaptureKit 与 screencapture 的 try?/空 catch → do-catch + stderr
- `NativeSessionStore`：提示词提交/历史翻页/取消中断分别记录 `promptSubmitError`/`historyLoadError`/`cancelAttemptError`
- `NativeCredentialStore`：**整表覆盖 → merge 只更新请求 refs**（修复抹除其他卡片凭据的缺陷）；空 catch 注释保留
- `NativeSettingsStore` / `NativeAgentPresetStore`：静默 return → `lastMutationError`/`lastOperationError`
- `NativeSplitContainer` fork/archive/addWorkspace：空 catch → `userVisibleError`
- `WorkspaceBrowserView` 拖拽重排：失败**回滚乐观更新** + `reorderError`
- `NativeUIManifest.route`：通用 catch 伪装 integrityNotVerified → **typed throws**（catch 只能捕到真实错误类型）
- `OfficialAccessibilityBaseline` / `NativeMarkdownRenderer` AttributedString：try? → do-catch + 具体错误信息
- `HostLifecyclePresentation.ready`：无官方就绪文案，加注释说明占位语义（消费方以 permitsInteraction 为准）

## 四、脆弱手写实现 / 性能（已修复）

- **`HostPathDisplay` 三元恒等死代码**（`? path : path` → `? path : "/" + path`）；Windows 盘符检测去魔数/去全量数组拷贝
- **callAsyncJavaScript API 误用**：`in: nil, in: .page`（编译为返回 Void 的同步重载、await 失效）→ `contentWorld: .page`（实测返回 `Optional<Any>`、await 生效），生产 4 处 + 测试 7 处
- `GhostPlaneBridgeWireDecoder` UUID 解析：map+allSatisfy+compactMap 三遍历 → 单遍历提前失败
- `GhostPlaneSkeleton`：elementSuffix/escape 多趟全量拷贝 → 单趟构建 + reserveCapacity；validAnchorKey/elementSuffix 共用判定
- `RPCModels.disposition`：contains 子串 → 精确匹配 + hasPrefix 兜底
- `SessionLogExporter` Content-Disposition：maxSplits 防分号截断、filename* 优先、引号剥离
- `NativeStatsDockPresentation`：字符串插值 Set → Hashable StepKey
- `NativeTrajectoryView`：text 重复 compactMap+joined → init 一次性求值
- `NativeToolViews`：重复 JSON 解析 → 统一 parseArguments
- `WorkspaceBrowserView`：搜索全量合并算两遍 → 一次计算复用；SessionStatusDot 点阵 → **共享 `NativeStateDotMetrics`**
- `NativePluginCardDraft` / `NativeSchemaFormDraft`：重复 JSONValue 路径扩展 → 提取单份 internal
- `RawEventReplayReducerTests`：4000 事件逐条 JSON 编解码 → 批量一次
- `SessionHistoryPagerTests`：私有单槽 AsyncGate（已知缺陷拷贝）→ 复用 RecoveryGate
- `HostPathAPITests`：UnsafeMutablePointer 裸指针 → [UInt8] 安全缓冲
- `ConversationNodeReducer.locationData`：全表 values 扫描 → key 前缀过滤
- 保留（记录理由）：GhostPlaneBridge wire 22 字段扁平 struct（协议重构风险>收益）；splitContainer objectWillChange 粗粒度监听（性能优化非缺陷）；NativeSessionStoreTests 111 处忙轮询（event-driven 重构风险大）；check-official-spec 循环 subprocess（CI 单次约 15s，可接受）；MaternMarkdown 手写高亮状态机（视觉敏感，配套测试完备）

## 五、正则滥用（已修复）

- `generate_ghost_plane_contract.py`：SLOT_RE/DATA_RE 正则解析 TS → **新建 extract_ghost_plane_ast.mjs（TS Compiler API）**，产物与仓库既有 JSON **字节级一致**
- `extract_brand_wordmark.sh` / `extract_fish_logo.sh`：sed 硬编码行号切片 → **AST 提取**（extract_official_icon_ast.mjs 扩展 FunctionDeclaration 支持），产物字节级一致
- `GhostPlaneContentSecurityPolicy.inject`：正则匹配 head → 前缀扫描首 `>`（无正则）
- `NativeMarkdownRenderer` sanitizer：新增行内代码占位符保护（代码块内容不再被 HTML/链接清洗吞噬）
- `check-markdown-links.py`：正则支持一层括号、剔除代码围栏
- `generate_official_transport_contract_manifest.py`：子串搜索 → 剥注释后 export 正则 + 边界
- `add_package_imports.py`：跳过文件头注释/编译指令后再定位 import 插入点
- `HostLogRedactor`（保留）：5 条链式替换是防御性脱敏而非结构解析、无灾难回溯，日志量小性能可忽略

## 六、验证结果

- `swift build`：**全量编译通过**（exit 0）
- `swift test --filter GlassSpecTests|GlassPortableCoreTests`：9/9 通过
- `swift test --filter GlassCoreTests`：（结果见下）
- 全部改动 Python 文件 `py_compile` 通过；门禁自测 `test-runtime-asset-inventory`/`test-package-target-graph`/`test-ci-workflow-layout`/`test_rc8_recapture_matrix`/`check-markdown-links` 全部 PASS
- 5 个 workflow YAML 全部合法
- `check-test-integrity.py`：91 个测试文件 **0 恒真断言命中**
- 变更规模：71 个文件，+868/-803（另删 27 个 portable-check 文件）

遗留（记录不处理）：GhostPlaneBridge wire 编解码扁平 struct、splitContainer 粗粒度监听、store 测试忙轮询、check-official-spec 循环进程、Markdown 手写高亮——均为"重构风险>当前收益"的判断取舍。
