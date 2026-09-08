# 分支审查台账 — `gpt-continue-todo-20260905` vs `main`

> 审查基准：官方 `~/deepseek-harness` = `dsh-v0.1.2-rc.1` / `a66e4702047846cdaa10c66c9d3df3951f5ea70d`（已核对）。
> 变更规模：281 个文件（A 89 / D 65 / M 97 / R 20）。
> 规则来源：`AGENTS.md` 十四严禁反模式 + 有效性第一性原理 + Swift 并发红线。
> 本文件只记录**已亲自核实（file:line + 代码证据）**的问题；待核实项单独标注。

## 严重度图例
- P0：生产崩溃 / 全局状态清空 / 数据损坏
- P1：韧性缺失（无自愈）、协议脆弱、性能灾难、门禁失真
- P2：代码质量 / 可维护性 / 命名与文档不符

---

## 已核实发现

### F1 [P0] 纯增量 Reducer 内残留 `precondition`，乱序/重复帧直接崩溃
文件：`glass/Sources/Core/Session/Projection/Conversation/ConversationNodeReducer.swift`
- L222 `precondition(existing.definition.kind == definition.kind && existing.id == result.id, ...)`
- L231 `precondition(previous.event.seq < match.event.seq, ...)`
- L235 `precondition(context.start == nil, ...)`
- L236 `precondition(context.matches.isEmpty, ...)`
- L266 / L268 / L313 / L315 `precondition(node.key == ... / node.target == ...)`
- L66 `precondition(Set(definitions.map(\.kind)).count == definitions.count, ...)`

`precondition` 在 **release 构建中依然生效**（不同于 `assert`）。`AGENTS.md` §1.4/反模式 1 明确要求纯 Reducer 零异常、乱序/未知 ID 只能无损对齐或单帧丢弃，物理剥夺局部错误导致上层 `invalidate()` 的权限。当前实现对非单调 seq、重复 start 直接 `SIGABRT`。
补充：同一分支内 `FIX_TODO.md` §2.3 声称已清除 11 处 `preconditionFailure`，实际只是把 `preconditionFailure` 换成了 `precondition`，并未消除崩溃面。

### F2 [P0] `RemoteEventRuntime` 任意流终止即清空整个会话目录，且消费 Task 不再自愈
文件：`glass/Sources/Core/Remote/RemoteEventRuntime.swift`
- L86-L100 `startConsuming()`：`for try await` 正常结束或抛错都调用 `invalidateCatalog()`。
- L226-L229 `invalidateCatalog()`：`catalog = nil; publishCatalog(nil)` —— 全应用会话树置空。
- L27/L28 `if eventTask == nil { startConsuming() }`：Task 结束后 `eventTask` 仍非 nil（未置 nil），因此后续 `open()` 不会重启消费，客户端永久失去 `$events` 增量（植物人态）。
违反反模式 13 与 §1.5 双态自愈机。

### F3 [P1] `RemoteMuxConnection` 对信封做“精确键数”断言，一帧异常拖垮整条 mux
文件：`glass/Sources/Core/Remote/RemoteMuxConnection.swift` L42-L101
- item/end/error 分支均以 `allKeys.count == 2/3` 严格相等判定，任何上游新增字段都 `throw protocolViolation`。
- `receiveLoop` L254-L264 把 `protocolViolation` 升级为 `source.cancel(...) + failAll(remoteError)`，即**一条 logical stream 的畸形帧会终止整条 WebSocket 上所有流的消费**。
违反韧性优先原则（未知字段应忽略、坏帧应隔离丢弃）。

### F4 [P1] `WorkspaceRuntime` 消费期无退避重连，非 carrier 错误永久清空工作区
文件：`glass/Sources/Core/Workspace/WorkspaceRuntime.swift`
- L99-L133 `runStreamLoop`：流正常结束 → `invalidate()`；抛错 → `invalidate()`，无 200ms→3s 指数退避、无重开 `workspace.follow`。
- L204-L209 `invalidate()`：`state = nil; publish(nil)`。
仅当 `$events` 同时失联、上层整体换 generation 时才会被重建；若只是 workspace 流单帧协议错误（`$events` 仍在），工作区列表永久空白。违反反模式 13 与 §1.5。
对比：`SessionRuntime.runFollowLoop`（`Runtime/SessionRuntime.swift` L201-L263）已正确实现 200ms→3s 退避，二者不一致。

### F5 [P1] 门禁脚本自身是“正则扫 Swift 源码”的伪门禁，且与工作流标注自相矛盾
文件：`glass/ci/check-test-integrity.py`
- 全文用 `re` 匹配 `glass/Tests/**/*.swift` 源码文本（L31-L49、L60-L92）判定“同义反复断言”。
- `AGENTS.md` §3.1 明令“严禁通过读取项目自身 `.swift` 源代码进行正则扫描、统计行数、或断言函数出现次数来充当单测”。该脚本正是被禁止的手段，且自认“Heuristic, not a parser”。
- 行为与命名矛盾：`.github/workflows/portable-checks.yml` L129 步骤名为 `Scan for tautological test assertions (report-only)`，但脚本 `main()` L111 `return 1 if total > 0 else 0` 是**硬门禁**；docstring 亦自称 advisory。
- 公平说明：分支把 main 上“`return 0` 永远绿 + 跳过 `*RecoveryGate*` 文件”改成了真实失败（这是一处真修复），但用启发式正则扫源码当硬门禁，一旦误报就会阻塞 CI；方向应改为由编译器/静态分析或干脆删除。

### F6 [P1] `check-official-remote-contract.py` 的“括号平衡”校验会误判函数类型
文件：`glass/ci/check-official-remote-contract.py` L62-L97 `validate_type_syntax`
把 `<`/`>` 当括号配对，遇到 TS 箭头类型 `=>` 中的 `>` 会报“unbalanced bracket”。
实测（调用该函数）：
```
FAIL (x: number) => void -> t: unbalanced bracket '>' in type '(x: number) => void'
FAIL () => Promise<void>    -> unbalanced bracket '>'
FAIL Map<string, () => void> -> unbalanced bracket '>'
```
当前锁定契约恰好无箭头类型，故未爆红；一旦官方新增函数类型参数即假红，属反模式 14 规则 2 的“栈式平衡”实现缺陷。

### F7 [P2] 认证 Host fixture 校验脚本存在未导入类型与死导入
文件：`glass/ci/check-authenticated-host-fixtures.py`
- L88 `def scan_for_unredacted_tokens(node: Any, ...)` 使用 `Any` 但 L4 未 `from typing import Any`（因 L2 `from __future__ import annotations` 才未在运行期 NameError）。
- L4 导入 `sys` 从未使用。
- L92 令牌键名白名单 `{"token","auth_token","launchtoken","access_token"}` 只检查 dict 键；L93 `v in (None, False, True, ...)` 因 `1 == True` / `0 == False` 会误放行数值 0/1。

### F8 [P2] 两条 workflow 对同一 fixture 的校验强度不一致
- `.github/workflows/native-ui.yml` L269-L277：先 `check-authenticated-host-fixtures.py`，再 `capture_authenticated_host_fixtures.mjs` 重新生成并 `cmp` 与签入 fixture 逐字节比较。
- `.github/workflows/portable-checks.yml` L117-L119：只跑校验脚本，**不重生成、不 cmp**。
结果：fixture 与生成器漂移只有在 macOS runner 才可能被发现，portable 门禁形同虚设。

### F9 [P2] “万级流式增量”单测没有任何时间/路径预算，无法证伪 O(N²) 回归
文件：`glass/Tests/Core/SessionProjectionIncrementalTests.swift` L214-L255
`testTenThousandLiveChunksStayOnIncrementalEnginePath` 仅断言最终 `text.count == 10_000` 与 journal revision；没有 `measure`/耗时断言，也不观测是否走了增量路径。若谓词回退为 O(N²)，测试仍会（极慢地）通过。`AGENTS.md` §3.4 要求核心状态机混沌/性能测试施加严格时间预算。

### F10 [P2] `NativeSessionStore` 仍保留 JSONValue→Data→Decodable 双重序列化热路径
文件：`glass/Sources/Core/Session/NativeSessionStore.swift` L3715-L3719
```swift
// TODO(perf): hot path — add JSONValue: Decodable to avoid encode→decode round-trip.
private func decode<Value: Decodable>(_ type: Value.Type, from value: JSONValue) -> Value? {
    guard let data = try? Self.jsonEncoder.encode(value) else { return nil }
    return try? Self.jsonDecoder.decode(Value.self, from: data)
}
```
反模式 3 明确禁止。核实使用点仅 L1278 `ImageAttachmentLimits`（图片附件，非每帧热路径），故严重度降为 P2，但 TODO 与代码本身仍属违规遗留。

### F11 [P2] `materializeAppended` 按 `Set` 无序迭代，非 chat 目标节点顺序可能不确定
文件：`glass/Sources/Core/Session/Projection/Conversation/ConversationNodeReducer.swift` L296-L326
`for key in affected { ... }`，`affected` 为 `Set<String>`；对 `target != "chat"` 且 `previous == nil` 的分支直接 `append`，顺序取决于 Set 哈希顺序（进程内随机化）。当单个事件同时命中多个 context 时，增量结果可能与全量 `rebuild()` 顺序不一致。需进一步构造用例确认可达性。

### F12 [P2] `SessionJournal` 大量 `snapshot!` 强制解包
文件：`glass/Sources/Core/Session/Runtime/SessionJournal.swift` L118、L128、L142、L144-L147、L159、L164、L184-L188
虽由前置 `guard snapshot != nil` 保证，但违反反模式 1“生产逻辑严禁强制解包”，且可读性差。

---

### F13 [P1] “官方 rc.1 Remote 契约清册”遗漏 commands / skills 两个命名空间，门禁盲区自我掩护
- 生成器 `tools/spec-generation/extract_official_remote_contract_ast.mjs` L43-L53 的 `SOURCE_PATHS` 只列 9 个包，**不含** `packages/interaction/commands/src/index.ts` 与 `packages/api/session-controller/src/skill-catalog.ts`。
- 实测：清册 51 个 procedure，缺 `commands/list`、`commands/execute`、`skills/list`（官方 rc.1 真实存在：`@Remote` 见上述两文件）。
- 门禁 `glass/ci/check-official-remote-contract.py` L19-L22 `REQUIRED_NAMESPACES` **恰好也不包含** `commands`/`skills`，因此永远发现不了遗漏；同时 `glass/ci/check-authenticated-host-fixtures.py` L62-L69 却断言真实 rc.1 Host 的 `commands/list`、`skills/list` 响应——两处自相矛盾。
- Swift 端 `RemoteEndpoint` 已声明 `commands/*`、`skills/*`，但清册与门禁并不校验它们，属“看起来完整、实则漏项”的合规门禁。

### F14 [P1] 双份 JSON 值枚举 + 双份 RPC 错误体系，热路径强制深拷贝
- `glass/Sources/Core/Remote/RemoteRPCModels.swift:6` 定义 `enum JSONValue`；`glass/Sources/Core/Remote/RemoteWireModels.swift:3` 定义结构完全相同的 `enum RemoteJSONValue`。
- 为桥接二者，`glass/Sources/Core/Session/Projection/Conversation/SessionConversationAdapter.swift:3-15` 对每个事件做递归 `map` 深拷贝（`conversationJSONValue`），逐帧额外分配。
- 同时并存两套 RPC 错误/回执体系：新 `RemoteConnectionError`/`RemoteFailurePayload` vs 旧 `DSHTransportError`/`RPCBusinessError`/`RPCServerRequest`/`RPCReceipt`（`RemoteRPCModels.swift:71-170`，仍被 `NativeSessionStore.swift:2304`、`Remote/SessionLogExporter.swift:66+` 使用）。违反反模式 9 的“传输机制与 DTO 契约严格分层”。

### F15 [P1] `HarnessHostController.recoveryAttempts` 永不复位，自愈只有一次额度
文件：`glass/Sources/Core/Host/HarnessHostController.swift`
- L37 声明；仅在 L124、L459、L520 被置 1，**全仓无任何 `recoveryAttempts = 0`**。
- 首次 carrier 丢失/进程退出会恢复；一旦恢复成功，后续任何再次失联（L455、L519 判 `== 0`）都直接 `.failed`，且用户手动 `retryOnce()`（L123）也永久失效。
- 对长时间驻留桌面端，第二次瞬时故障即不可自愈，违反 §1.5 双态自愈。

### F16 [P2] `RPCBusinessError.disposition` 用臆测字符串变体猜错误分类
文件：`glass/Sources/Core/Remote/RemoteRPCModels.swift:76-105`
硬编码 `revision_conflict`/`revision-conflict`/`conflict`/`stale`/`validation_invalid`/`method_not_found`/`session-not-found`… 数十个自造变体，再用 `hasPrefix` 兜底。官方 rc.1 的错误码是**已由 AST 清册确定**的闭集（`official-remote-contract-manifest.json` 的 38 个 code），应按闭集确定性映射，而非猜测式子串匹配（反模式 4/14）。

### F17 [P2] 仓库内并存两个“官方基准 commit”，与分支自己的 SSOT 规则冲突
- `glass/Sources/Spec/OfficialUISpec/official-ui-catalog.json` 的 `officialSourceCommit` 仍是 `b150a551b8d465e31e418e1b2eaf5e79bbb7d28e`。
- `glass/ci/check-official-spec.py:26-31` 新增 `LEGACY_UI_CATALOG_COMMIT=b150a55…` 与 `CURRENT_VISUAL_SCENE_COMMIT=a66e470…` 两个常量，显式把旧 commit 钉死。
- 但分支新增的 `notes/RC1_SOURCE_OF_TRUTH.md` 第 42-46 行规定“任何 Glass contract/fixture/spec 只有 provenance 指向 a66e470 才算 current”。二者直接冲突。

### F18 [P2] 视觉重认证矩阵是源码文本“对暗号”，且所有场景 report-only 永不失败
文件：`glass/ci/test_rc1_recapture_matrix.py`
- L90-L92：`require(marker in capture, ...)`、`require(scene in workflow, ...)` 纯子串匹配项目自身 TS/YAML 文本；注释里出现场景名即可满足，违反 §3.1。
- L86 强制 `mode == "report-only"`；`glass/ci/compare_visual_pair.py:206` 仅在 `mode == "enforce"` 时才 `SystemExit`。故全部 16 个场景的像素差异都不会让 CI 变红。

### F19 [P2] Ghost Plane 契约生成器仍以子串匹配判定官方 loader wire
文件：`tools/spec-generation/generate_ghost_plane_contract.py`
- L126-L129 `if any(term not in module_manifest ...)`、`if "return \`/plugins/??${resources}&rev=${rev}\`" not in module_host` 对官方 TS 源码做字符串包含判断（注释/死代码也能通过）。
- L98-L113 `slot_anchor` 是手写 `startswith` 分类器，新增 slot 即 `SystemExit`。
（slot/selector 本身确为 AST 提取，见 `extract_ghost_plane_ast.mjs`，这部分是好的。）

### F20 [P2] 安全 Markdown 净化器编译失败时静默退化为空正则（会破坏文本）
文件：`glass/Sources/UI/Conversation/NativeMarkdownRenderer.swift:13-20,64`
把 `try!` 改成 `(try? NSRegularExpression(...)) ?? NSRegularExpression()`。空 `NSRegularExpression()` 匹配零宽位置，`stringByReplacingMatches` 会在每个字符边界插入替换串——安全边界失效且文本被破坏，比崩溃更隐蔽。正确做法是这些常量模式用可验证的静态初始化（编译期保证），或失败时 fail-closed 返回原文本而非“空正则”。

### F21 [P2] `HostLogRedactor` 注释谎称 O(1)，实际每次 `lowercased()` 全量拷贝
文件：`glass/Sources/Core/Host/HostDiagnostics.swift:172-184`
`let lowered = text.lowercased()` 是 O(n) 分配，随后 6 次 `contains` 扫描，注释却写 “Fast-path O(1) keyword scan”。且 `Rule.init` 同样 `?? NSRegularExpression()`。

### F22 [P2] 残留强制解包
- `glass/Sources/Core/Session/Projection/SessionProjectionStore.swift:52` `existing!`
- `glass/Sources/Core/Session/Runtime/SessionJournal.swift:118,128,142,144-147,159,164,184-188` 共 10 处 `snapshot!`
违反反模式 1（虽当前有前置 guard，仍属禁止写法）。

### F23 [P2] 156 处注释仍写 `RC8`，与分支自称的 rc.1 基准不一致
例：`glass/Sources/Core/Remote/RemoteDTOModels.swift:3` “Source: locked RC8 `host.openPath`”、`glass/Sources/Core/Remote/DomainAPIs.swift:7,34,55,157,173`。分支已把文档/工作流改名为 rc.1，源码注释未同步（反模式 4 轻度）。

### F24 [P2] 测试专用 fixture 目录类型编译进生产 target
`glass/Sources/Core/Remote/OfficialAuthenticatedHostFixtureCatalog.swift`、`OfficialRawEventReplayFixtureCatalog.swift` 位于 `Sources/Core`（GlassCore 生产库），仅被 `glass/Tests/**` 使用；增加生产包体积与公开面。

### F25 [P2] 交互场景门禁不再校验 visual artifact 是否存在
文件：`glass/ci/check-official-interaction-scenes.py` `upstream_path`
对 `artifacts/official-webui/...` 分支由“在 repo/visual-review/design-reference 中查找真实文件”改为**无条件 `return`**；场景清册可登记不存在的截图而 portable 门禁照过。

---

## 测试质量专项（已逐条回读核实）

### T1 [P1] `NativeSessionStoreTests` 由 83 个测试函数砍到 26 个，交互/队列竞态覆盖归零
`git show main:glass/Tests/Core/NativeSessionStoreTests.swift | grep -c 'func test'` = 83；当前 = 26。
被删且无替代的行为测试（main 行号）包括 `testDisconnectCancelsPendingApprovalSubmissionBeforeLateFailure`(main:2239)、`testReplacingApprovalCancelsOldSubmissionBeforeItCanMutateNewRequest`(main:2270)、`testPendingApprovalAndQuestionClearOnlyOnMatchingHostResolution`(main:2422)、`testQueueActionFailureIsScopedToTheActionAndDoesNotRetireRow`(main:1859) 等约 40 个。
而生产侧 `NativeSessionStore.swift` 仍保留 `pendingApproval/pendingQuestion/isSubmittingApproval/queueUpdateTask` 等 94 处引用——被删的是**仍在服役**的竞态防护测试。

### T2 [P1] 单测自行注入被断言的值，掩盖了“Host 投影→Store”真实链路
文件：`glass/Tests/Core/NativeSessionStoreTests.swift:78-90`
测试直接 `store.projections.apply(sessionID:..., key:"imageLimits", value:.object([...]), seq:0)`，随后 `await eventually { store.imageAttachmentLimits != nil }` 必然成立。新测试助手的 `sessionRuntime` 默认为 nil，生产走 `NativeSessionStore.swift:1522-1537` 的 `guard let sessionRuntime else { … }` 分支，根本不会消费 `RejectingSessionAPI.history()` 提供的投影；该链路若回归测试仍绿（可证伪性缺口）。

### T3 [P1] `GhostPlaneLoopbackPolicy` 安全拒绝分支的测试被删光，生产仍在执行
文件：`glass/Tests/Core/GhostPlaneLoopbackPolicyTests.swift:20-30`
现在只覆盖 `unsupportedScheme/unregisteredPlugin/malformedCombo/nonPluginPath`；`.credentialedURL`、`.wrongPort`、`.nonLoopbackHost`、`.encodedTraversal`、构造期 `.invalidOrigin`（https/localhost/带凭证/port 0）的用例全部删除，而生产 `GhostPlaneLoopbackPolicy.swift:40-49` 与 `isCanonicalLoopbackOrigin` 仍在执行这些拒绝。全仓测试已无任何对上述 denial 的引用。

### T4 [P1] 守护“万级流式不退化 O(N²)”的测试无法证伪
同 F9。`SessionProjectionIncrementalTests.swift:214-255` 无时间/路径预算，`journalFoldPlan` 即使每轮返回 `.replace` 也得到相同最终快照并通过。

### T5 [P2] “PrunesOldestRawEvents” 测试根本没触发裁剪
文件：`glass/Tests/Core/SessionJournalTests.swift:203-211`
`XCTAssertEqual(snapshot.records.count, 2100)`——但 `records` 从不裁剪（只有 `rawEventsBySeq` 上限 2000，`SessionJournal.swift:66/208-215`）。测试名与断言不符，且 `2100` 是镜像 fixture 的魔数。

### T6 [P2] 混沌风暴缺时间预算；工作区“不变量 2”恒真
- `WorkspaceRuntimeInvariantTests.swift:93-138`、`SessionJournalRecoveryChaosTests.swift:24-153` 有确定性 PRNG 与不变量，但无 `<50ms` 或显式预算（§3.4）。
- `WorkspaceRuntimeInvariantTests.swift:137` `XCTAssertEqual(state.generation.rawValue, 1)` 恒真：Reducer 从不改 `generation`。

### T7 [P2] 硬编码魔数镜像 fixture/静态常量
- `GhostPlaneSlotRegistryTests.swift:7-8` `slots.count == 25`、`greenSlots.count == 20`（fixture 恰好 25）。
- `GhostPlaneSkeletonTests.swift:37` `requiredSelectors.count == 8`（镜像 `GhostPlaneSkeleton.swift:75-84`）。
官方上游合法新增 slot/selector 即假红（反模式 14）。

### T8 [P2] 断言镜像无条件常量 + fixture 数据变成死数据
文件：`glass/Tests/App/NativeModelDirectoryStoreTests.swift:28-29`
`XCTAssertTrue(store.groups.isEmpty)` / `failures.isEmpty`；生产 `NativeModelDirectoryStore.swift:40-41` 无条件写死 `groups = []`/`failures = []`（注释称 rc.1 无 `llm/models` authority），而 fixture（L14-20）仍喂入 groups/failures——断言永不失败，fixture 数据被静默丢弃。

### T9 [P2] 终端状态优先级测试名不副实
文件：`glass/Tests/App/NativeAccessibilityRuntimeTests.swift:417-437`
用例名 `SignalBeforeNonZeroExit`，但 fixture 里没有任何 exit code，`forbidden: ["exit code 7"]` 恒真；生产 `NativeRawToolCardProjector.swift:217-237` 只会产出 signal 或 exitCode 之一。

### T10 [P2] `XCTAssertThrowsError` 丢掉错误分支校验
文件：`glass/Tests/Core/GhostPlaneSkeletonTests.swift:40-48`
两个用例均无 error handler；原版本断言 `.duplicateAnchorKey`/`.invalidAnchorKey`，现在任意无关 throw 都能通过。

### T11 [P2] 断言完整人类可读文案，重构不友好
文件：`glass/Tests/Core/HostBuildClassifierTests.swift:24-28,47-62`
整枚举相等包含 `reason:` 文案，改一句提示即假红（违反 §3.2）。

### T12 [P2] `measure` 无基线永不稳定失败；顺带删掉 disposition 断言
文件：`glass/Tests/Core/RawEventReplayReducerTests.swift:182-186,194`
`measure(metrics:[XCTClockMetric()])` 未配 baseline/`XCTMeasureOptions`，只报告不失败；L194 把原来的 `.immediate` 断言降级为 `_ = reducer.append(...)`。

### T13 [P2] 以固定 sleep 断言“没有发生”
- `SessionRuntimeResilienceTests.swift:151` 睡 100ms 后断言 `followCallCount == 1`；延迟重连仍可通过。
- `NativeSessionStoreTests.swift:407` 睡 30ms 后断言 `promptContents.isEmpty`。

### T14 [P2] fixture 字面量自断言
文件：`glass/Tests/Core/AuthenticatedHostFixtureTests.swift:14`
`XCTAssertEqual(fixture.fixtureRevision, "official-a66e470-authenticated-host-r2")` 只是复述 JSON 字段；真正有意义的是 L13 的 `officialSourceCommit == OfficialUISpec.Build.sourceCommit`。

### T15 [P2，已与 F2/F4 相互印证] 测试把“流正常结束即丢弃全部 authority”固化为期望
- `WorkspaceRuntimeLifecycleTests.swift:7-45` 断言 `finish()` 后 `state == nil`。
- `SessionControlRuntimeTests.swift:160-179` 断言正常结束发布 nil。
结合 F2/F4（运行时无消费期重连），这正是 AGENTS §1.5 禁止的“植物人态”，测试反而把它锁死。

### T16 [P2] AppKit 测试窗口 settle 时间由 0.1s 砍半到 0.05s
文件：`glass/Tests/App/IsolatedTestWindow.swift:13` `settleTime: TimeInterval = 0.05`；被替换的 `NativeMaterialIsolationRuntimeTests`/`NativeWebViewIsolationRuntimeTests` 原为 0.1s，收紧布局等待窗口，增加偶发假红风险。

---

## CI / 生成器专项（已逐条回读核实）

### S1 [P1] Ghost Plane 契约选择器清单由“AST 全量闭包”退化为硬编码 8 项
文件：`tools/spec-generation/generate_ghost_plane_contract.py:88`
```python
selectors = sorted(required_data_selectors)
```
- `main` 为 `sorted(data_selectors | {[data-slot=...]} | {"[data-slot=tool.call.toolview]"})`，即 AST 发现的全集。
- 实测 `node tools/spec-generation/extract_ghost_plane_ast.mjs ~/deepseek-harness`：AST 发现 **16** 个 `data-*` 锚点；当前 fixture 只记录 **8** 个。
- 被丢弃的真实锚点：`[data-chat-turn]`、`[data-dragging]`、`[data-side]`、`[data-turn-process-answer]`、`[data-turn-process-hidden]`、`[data-turn-process-inline]`、`[data-turn-process-member]`、`[data-width-handle]`。
- `check-official-ghost-plane-contract.py` 是“候选 vs 基线”比对，基线又由同一个缩水生成器产出，因此**永远发现不了这 8 个锚点的丢失**——自洽式假门禁。

### S2 [P2] 视觉 artifact 存在性校验被删除（与 F25 同源，独立核实）
`glass/ci/check-official-interaction-scenes.py:55-58` 对 `artifacts/official-webui/**` 无条件 `return`；18 个场景中 15 个的 `ariaBaseline`/`screenshotBaseline` 仅凭前缀即通过，路径打错或文件缺失都无法让该门禁变红。

### S3 [P2] 分支修好了一个无人调用的生成器（死代码）
`tools/spec-generation/generate_official_locales.py:54-65` 删除了 `/home/ubuntu/...` 硬编码（真修复），但 `glass/ci/check-official-locales.py:19` 实际调用的是 `generate_official_locales.ts`（自带内联 AST，L188），**从不调用该 .py**。CI 效果为零，且仓库存在两套分叉实现。

### S4 [P2] 既有硬门禁被降级为永远绿
`.github/workflows/portable-checks.yml:131-132` 改为 `python3 tools/check-doc-style.py`（main 为 `--fail`）；`check-doc-style.py:103-106` 无 `--fail` 时只能 `return 0`。

### S5 [P2] 门禁脚本无人调用（孤儿）
`glass/ci/test-assemble-resource-bundle.sh` 本分支更新了 fixture 文件名，但**任何 workflow/脚本都未引用它**（实测 grep 为空；仅 `TODO.md:91` 声称已接入 portable-checks，属虚假记录）。

### S6 [P2] TS 编译器解析回退链可静默使用无关 TypeScript，且 `catch {}` 吞错
`tools/spec-generation/extract_official_remote_contract_ast.mjs:17-22` 把 `resolve(process.env.HOME||'', 'deepseek-harness')` 列入回退根；L14/L28/L36 均为裸 `catch {}`，CI 配置错误被静默吞掉。

### S7 [P2] `closedRemoteErrors` 是“抛出点集合”而非声明闭包
`extract_official_remote_contract_ast.mjs:240` 只从 `new RemoteError('<literal>')` 收集；官方锁定源 `RemoteErrorDetailsMap` 声明 57 个 code，仅 38 个被发出（子代理用 TS API 计数）。缺失的 19 个（如 `gateway/ambiguous-endpoint`、`gateway/arguments-invalid`）不会让门禁报警。

### S8 [P2] 认证 fixture 门禁硬编码金值而非候选/基线 diff
`glass/ci/check-authenticated-host-fixtures.py:26,35,64,81` 把 `fixtureRevision`、auth 事实字典、命令名列表、content-disposition 全部写死；任何合法 rc.1 重采样都要手改门禁。（native-ui 另有 fresh capture + `cmp` 兜底，故降为 P2。）

### S9 [P2] 琐碎：未使用导入
- `glass/ci/check-authenticated-host-fixtures.py:4` `sys` 未用；`:88` `Any` 未导入（靠 `from __future__ import annotations` 侥幸）。
- `tools/spec-generation/generate_official_remote_contract_manifest.py:8` `import re` 未用。

---

## Host / Controllers 专项（已逐条回读核实）

### H1 [P1] `$events` 运行时恢复无指数退避
文件：`glass/Sources/Core/Host/HarnessHostController.swift:408-411` → `reconnectRemote` (419-465)
`case .failed(error) where error.category == .carrierLost:` 立即 `reconnectRemote`，全程无 `Task.sleep`；一次失败即重启进程或永久 `.failed`。同仓 `SessionRuntime.swift:201-253` 已有 200ms→3s 退避范式。`grep backoff/Task.sleep` 在 `Core/Host`、`Core/Remote` 为空。

### H2 [P1] 一个未知/畸形 `$events` 帧即永久失败并断开整个应用
文件：`HarnessHostController.swift:412-415`
`.ended` 与非 `carrierLost` 的 `.failed` 都走 `failRemoteGeneration` → `.failed`；`App/DeepSeekHarnessGlassApp.swift:78-80` 把 `.failed` 映射为 `windowCoordinator.disconnectHost()`（清空全部 runtime、回到 welcome）。而 `RemoteConnection.swift:177-180` 把任何无法解码的帧变成 `.failed(protocolViolation)`。即：未来官方新增一种帧类型 → 整个 App 掉线。违反“局部解析失败不得清空全局状态”。

### H3 [P2] `CommandsController` / `SkillsController` 构造后无人消费
文件：`glass/Sources/Core/Controllers/HarnessControllers.swift:13-14`
`CommandsControllerAPI`/`SkillsControllerAPI` 仅自身定义，全仓无消费者；`controllers.commands`/`.skills` 无任何 UI 读取（实测 grep 为空）。约 150 行 RPC facade 为死代码（并与 F13 的 commands/skills 契约缺项呼应）。

### H4 [P2] Host 启动未加 `--no-open`，进程 token 可能进入用户浏览器历史
文件：`glass/Sources/Core/Host/HarnessHostProcess.swift:19`
`arguments: [..., "web", "--port", "0"]`；官方 `packages/bundle/web-app/src/index.ts:61` `openBrowser` 默认 `true`，且 `:271/:284` 用 `authenticatedUrl`（`browser-auth.ts:223-228` 会把 launch token 放进 `?token=`）打开默认浏览器。Glass 自己会 fetch 该 URL 完成鉴权，无需 Host 再开浏览器。属 main 遗留，但本分支新建文件集中了这些参数。

### H5 [P2] `streamState` 可能显示 `connecting` 而 `lifecycle=ready`
文件：`HostDiagnostics.swift:92`（`.ready` 分支未设置 streamState）与 `HarnessHostController.swift:22`（`didSet` 起非结构化 Task 读 `self.state`）。诊断文本可能自相矛盾。

### H6 [P2] `redactSecrets` 在 MainActor 上对每段 stderr 跑 3 遍正则
文件：`HarnessHostController.swift:552,561-578`
与同文件已有的编译期规则 + 关键字快路径 `HostLogRedactor`（`HostDiagnostics.swift:135-180`）重复实现。

### H7 [P2] “已验证构建”的 UI-spec 校验分支对当前目录永不可达
文件：`HarnessHostController.swift:105-118`
`SupportedHostBuilds.json` 唯一条目 `verificationState = "planned"`，`HostBuildClassifier` 永远返回 `.bestEffort`，故 `case .verified` 的 `isCompatible/sourceCommit/uiSpecRevision` 校验与失败文案是死代码（实测）。

### H8 [UNVERIFIED] `commands/execute` 发送 `images` 与已生成 descriptor 可能不一致
`glass/Sources/Core/Controllers/CommandsController.swift:107` 发送 `images`；官方源码 `packages/interaction/commands/src/index.ts:340` 确有 `images` 参数，但仓库内已生成的 `packages/api/remotes/lib/client.js:4299` 只列 `agent`+`line`。若打包的 payload 使用旧 lib，gateway 的 `assertExactArguments` 可能拒绝。无法在本机确认实际打包产物。

---

## PluginPlane / UI 专项（已逐条回读核实）

### G1 [P1] `web_fetch` 原生卡片被丢弃（本分支引入的功能回归）
- `glass/Sources/UI/Tooling/NativeToolViews.swift:231` 与 `:1163`：`guard invocation.name == "web_search" else { return nil }`。
- Core 对 `web_fetch` 投影 `.fetch`：`NativeRawToolCardProjector.swift:429`；测试 `NativeRawToolCardProjectorTests.swift:151-158` 也断言 `.fetch`。
- `main` 的 `web` 属性走 `NativeWebCardPresentation.resolve(...)`，无名称白名单；本分支改为 raw projector 并加了只含 `web_search` 的守卫，导致 `web_fetch` 退化为通用文本卡片、Core 的 `.fetch` 分支成为不可达死代码。UI 层白名单无测试覆盖（P2-5 的两份白名单已漂移）。

### G2 [P1] Markdown 热路径存在 O(n²) 正则（实测）
文件：`glass/Sources/UI/Conversation/NativeMarkdownRenderer.swift:13-20`，调用点 `:44-48`、`:352`（accessibilityLabel）、`:375/:387/:410/:478`（SwiftUI `Text` 构造，主线程）
本机 `NSRegularExpression` 实测（/tmp/redos.swift）：
```
pattern0 `<script>…` 64KB → 2.877s
pattern1 `[[[…`       64KB → 20.200s
```
每翻倍约 4 倍（O(n²)）。`:40-42` 的 `contains("<")||contains("[")` 快路径对这些输入无效。`swift-markdown` 已是依赖且本文件 `:158` 已用 `Document(parsing:)` 做块解析；内联处理应改用解析器或 O(1) 前后缀切片。

### G3 [P1] 官方 `tool.call.toolview` 槽位被删除且被门禁禁止
- `glass/Sources/Core/Plugin/OfficialGhostPlaneContract.swift:73` 断言 fixture 不得含 `tool.call.toolview`；`glass/ci/check-official-ghost-plane-contract.py:53-54` 同样禁止。
- 但官方 rc.1 确实声明：`~/deepseek-harness/packages/client/ui-tool/src/client/contract/slots.ts:26`（`kind:'keyed'; scope:'session'`），并由 `ui-skill/src/client/index.ts:69` 注册。
- 生成器 slot 源只有 ui-conversation + ui-chat 两个包（`extract_ghost_plane_ast.mjs:29-32`），所以 25-slot fixture 是**两个包的子集**，门禁还把官方 key 当“legacy”拒绝。第三方插件无法再注册官方 keyed 工具视图槽。

### G4 [P2] 运行时契约门禁硬编码魔数
`OfficialGhostPlaneContract.swift:66,68`：`sources.count >= 8`、`slots.count == 25`；无法发现“数量对但内容被截断”的 fixture，且上游合法增删即假红（反模式 14）。

### G5 [P2] 安全净化器 fail-open
同 F20；实测空 `NSRegularExpression()` 返回 0 匹配，即未来某 pattern 编译失败会静默关闭 HTML/script 剥离。

### G6 [P2] 生产代码残留强制解包
`glass/Sources/PluginPlane/GhostPlaneTemporaryFileStore.swift:131`、`glass/Sources/Core/Plugin/GhostPlaneSkeleton.swift:135,145`。

### G7 [P2] 工具名白名单在两处重复并已漂移
`NativeToolViews.swift:211-232` 与 `:1147-1164` 各有一份 bash/pwsh/read/write/grep/glob/web_search 列表；漂移直接导致 G1。应从 Core projector 派生单一谓词。

### G8 [P2] `official-interaction-scenes.json` 被压成 1 行 19,383 字节
（原 292 行，场景集未变）——diff 不可审查，违背反模式 2 的可审查性精神。

### G9 [P2] 布局回调中修改父 `NSSplitViewController` 的 `minimumThickness`
`glass/Sources/UI/Sidebar/OfficialSidebarHostController.swift:39-46` 在 `viewDidLayout()` 内写父容器 split item（虽有 `!=` 守卫，仍属布局期副作用，可能触发再次布局）。

### G10 [P2] 自定义 scheme handler 在主线程整文件读取 + ACAO `*`
`GhostPlaneTemporaryFileStore.swift:101` `Data(contentsOf:options:.mappedIfSafe)`、`:113` `Access-Control-Allow-Origin: *`。大附件会阻塞 handler 线程，且通配来源比单文档平面所需更宽。

---

## 已确认“良好”项（避免误伤）
- `WorkspaceStateReducer.reduce` 已用 `uniquingKeysWith:` 与防御性 order 对齐（L36-L48），反模式 1/13 的字典构造已修。
- `SessionRuntime.runFollowLoop` 已实现协商期上抛 / 消费期 200ms→3s 指数退避（L201-L263）。
- `RemoteEventRuntime.applySessionFrame` 对未知 sessionId 的 status/activity 静默忽略（L147-L158），不再抛错清空。
- 源树内无 `try!`；无硬编码 `/home/ubuntu`、`/Users/...` 路径；`check-official-remote-contract.py` 已去魔数（不再 `== 51 / == 38`）。
- `tools/spec-generation/extract_official_remote_contract_ast.mjs` 确为 TypeScript Compiler API AST 提取（`ts.isInterfaceDeclaration` / `ts.isMethodDeclaration`），非正则。
- 协议/文案核对通过：`session/list` 的 `_request`、`RemoteSessionSummary`、`RemoteModelCatalog`、`MessageFeedback*` 错误码与 payload、`ApprovalOutcome`、`ASK_CANCELLED` + `UserQuestionError`、`{answers:[{id,selected,custom}]}`、composer 占位符、`details.input` ∈ `ui-chat`、workspace follow 帧、`/plugins/??…&rev=…` 均与 `~/deepseek-harness@a66e470` 一致。
- `check-test-integrity.py` 把 main 的永远绿 `return 0` 改成 `return 1 if total>0`（真修复；当前 0 命中 / 109 文件）。
- `check-official-ghost-plane-contract.py` 已接入 native-ui，候选/基线 diff，slots 为完整 25 项 AST 闭包。
- `tools/check-host-upgrade-report.py` 仅做结构化校验，负例为进程内 deepcopy（非子进程套娃），已被 release.yml/documentation-integrity.yml 调用。
- 被删除的脚本/门禁无任何 workflow 悬挂引用；删除的 `test-official-ghost-plane-contract.py` 确为“子进程 + 硬编码报错串”套娃。
- `official-authenticated-host-fixtures.json` 无路径/UUID/时间戳泄漏。
- `SessionJournalRecoveryChaosTests`、`WorkspaceRuntimeInvariantTests`、`SessionCommandServiceTests`、`RemoteInteractionProjectorTests` 等为真实行为测试（详见 T 段）。

---

## 实跑证据（本轮）
- `swift build --package-path glass` → `Build complete!`，exit 0，无警告。
- `swift test --package-path glass` → **Executed 475 tests, 27 skipped, 0 failures, 19.73s**，exit 0。
- `python3 glass/ci/check-test-integrity.py` → `scanned 109 test files; 0 files flagged; 0 tautological assertions`，exit 0。
- `node tools/spec-generation/extract_ghost_plane_ast.mjs ~/deepseek-harness` → 16 个 data-* 锚点 vs fixture 8 个（S1 证据）。
- 官方基准核对：`git -C ~/deepseek-harness rev-parse HEAD` = `a66e470…`，`describe --tags` = `dsh-v0.1.2-rc.1`。

---

## 优先级修复建议（按危害/成本排序）
1. **F2 / H2（P0/P1）**：`RemoteEventRuntime.invalidateCatalog()` + `HarnessHostController` 把 `.ended`/非 carrier `.failed` 直接 `.failed`→`disconnectHost()`；一帧未知类型即掉线。改为消费期退避重连 + 坏帧隔离丢弃。
2. **G2（P1）**：Markdown 净化器 O(n²) 正则（实测 64KB → 20s）。改用已链接的 swift-markdown 解析器或 O(1) 切片。
3. **F1（P0）**：`ConversationNodeReducer` 的 8 处 `precondition` 改为容错分支（`ConversationCoreNodes` 已修，Reducer 未修）。
4. **F13 / S1 / G3（P1）**：三处“AST 提取源清单不完整 + 门禁所需集合恰好排除缺项”的自洽盲区（Remote commands/skills、Ghost Plane selectors、tool.call.toolview）。补全源清单，门禁改为“AST 全量闭包 vs 基线”。
5. **F4 / F15 / H1（P1）**：`WorkspaceRuntime`/`SessionControlRuntime` 消费期无退避；`HarnessHostController` 无退避且 `recoveryAttempts` 永不复位。统一复用 `SessionRuntime` 的 200ms→3s 退避。
6. **T1 / T3（P1）**：恢复被删的交互/队列竞态与 loopback 安全拒绝测试。
7. **G1（P1）**：`web_fetch` 白名单一行修复。
8. **F17 / F23（P2）**：统一到 a66e470 单一基准，清理 156 处 RC8 注释。
9. **F5 / S3 / S5 / S4（P2）**：删除/重写源码正则门禁；补齐孤儿门禁；恢复 doc-style 硬门禁。

---

## 覆盖度证明
- 281 个改动文件：89 A / 65 D / 97 M / 20 R（其中 18 个为 `git diff -M --numstat` 证明的 **0/0 纯移动**，无内容变化）。
- 逐文件审查覆盖：Core/Remote 全部、Core/Session Runtime+Projection 全部关键文件、Core/Host 全部、Core/Controllers 全部（协议逐条核对官方）、Core/Plugin 全部、PluginPlane 全部、UI 全部改动点、Tests 全部 72 个改动测试文件（子代理逐文件 + 本 Agent 抽样回读）、CI/生成器全部、docs/workflows/Package 全部。
- 生成的 JSON fixture（official-remote-contract-manifest、official-authenticated-host-fixtures、official-ghost-plane-contract、official-ui-spec-build、official-locales、visual/interaction scenes、HostUpgradeReport、RuntimeAssetInventory）由对应门禁做候选/基线或结构校验；已抽查 provenance commit 与字段。
- 实跑：`swift build` 0 警告 exit 0；`swift test` 475 tests / 27 skipped / 0 failures；`check-test-integrity.py` 0 命中。

## 待核实 / 后续轮次
- [x] 109 个测试文件专项审查（T1-T16，已回读核实关键项）
- [ ] `NativeSessionStore.swift`（+1904 行）剩余段落逐段审查
- [x] `Core/Controllers/*` 抽样核对（Session/Goal/MessageFeedback/Workspace 已核对协议）
- [ ] `Core/Host/*` 剩余（生命周期/并发）——已发现 F15；等待 Host 子代理结果
- [ ] `Core/Plugin/*` + `PluginPlane/*` 剩余——等待 PluginPlane 子代理结果
- [x] `UI/*` 关键点（Markdown 正则、ToolViews 双解码）——F20/F21
- [x] `tools/spec-generation/*`（S1-S9）
- [ ] 逐文件确认“纯 rename（18 个）”确实无内容变化
- [ ] 汇总最终报告

---

# 第二轮：修复实施记录（目标：完整、优雅地修复 + 删除垃圾测试）

## 已修复（代码）
| 发现 | 修复 |
|---|---|
| F1 | `ConversationNodeReducer` 移除全部 `precondition`：非单调/重复 start/身份冲突改为丢帧或降级为 update；node key/target 不匹配跳过 |
| F2/H2 | `RemoteEventRuntime` 流终止不再清空 catalog；`RemoteMuxConnection` 容忍未知字段、未知帧类型忽略、坏 item 只失败本流；`HarnessHostController` 对 `.ended`/非 carrier 失败也走退避重连 |
| F3 | mux 信封不再精确键数断言；删除未用的 `DynamicKey` 常量 |
| F4 | `WorkspaceRuntime` 消费期加入 200ms→3s 指数退避重连；删除 `invalidate()` 清空 |
| F15/H1 | `HarnessHostController.reconnectRemote` 加入 6 次退避重试；`publishReady` 复位 `recoveryAttempts` |
| G2 | `NativeMarkdownSecurityPolicy` 用线性扫描器替换 4 条正则（实测 64KB `<script>`/`[` 不再 O(n²)） |
| G1/G7 | 新增 `NativeToolRowModel.isWebTool`，row 与 details 共用，纳入 `web_fetch`；新增回归测试 |
| F13/S7 | Remote AST 提取器补 `commands`/`skills` 源文件，`closedRemoteErrors` 改为完整声明闭包（54 procedures / 57 errors）；门禁 `REQUIRED_NAMESPACES` 补两项 |
| S1/G3/G4 | Ghost Plane 生成器纳入 `ui-tool` 槽位（`tool.call.toolview` 归 red/chat），新增 `dataSelectors` 全量闭包；移除 `slots.count==25`、`sources.count>=8` 魔数与“禁止 toolview”断言 |
| F14 | 删除重复的 `enum JSONValue`，改为 `typealias JSONValue = RemoteJSONValue`，移除逐帧深拷贝 |
| F6 | 契约类型校验识别 TS 箭头 `=>`，不再误报括号不平衡 |
| F16 | 删除仅被测试使用、且靠臆测字符串前缀分类的 `RPCErrorDisposition` 与两个 `disposition` |
| F20/G5 | Markdown 净化器不再有 `?? NSRegularExpression()` fail-open 兜底 |
| F21 | `HostLogRedactor` 注释修正；`redactSecrets` 删除并统一委托；规则编译失败跳过而非空正则 |
| F22 | 移除 `SessionProjectionStore.existing!`、`SessionJournal` 10× `snapshot!`、`GhostPlaneTemporaryFileStore` URL `!`、`GhostPlaneSkeleton` 两处 `!` |
| F23 | Sources/Tests 内 `RC8`/`rc.2` 全部改为 `rc.1` |
| H4 | Host 启动参数加 `--no-open`（防 launch token 进浏览器历史），测试同步 |
| H5 | `HostDiagnostics` `.ready` 设置 `streamState = ready` |
| H6 | 删除重复的 `redactSecrets` |
| G9 | 侧栏 `minimumThickness` 移到组合期设置，删除 `viewDidLayout` 布局期副作用 |
| S3 | 删除死代码 `generate_official_locales.py`/`extract_official_locales_ast.mjs`，修正 `.ts` 的 `GENERATOR_NAME` 并重生成 catalog |
| S6 | AST 提取器移除 `$HOME/deepseek-harness`/cwd 回退，只用锁定官方 root 或仓库 pinned typescript |
| S9 | 清理未使用导入 |
| T5/T6/T7/T9/T10/T11/T12/T14/T16 | 重写为可证伪断言（裁剪效果、时间预算、错误分支、无魔数、无文案耦合、无 measure 空跑） |
| T15 | 重写 `WorkspaceRuntimeLifecycleTests`/`SessionControlRuntimeTests`，验证“保留 authority + 退避重连”新语义 |
| F19 | Ghost Plane 模块 loader wire 校验改为 TS AST 提取（`moduleLoaderWire`），删除官方源码子串匹配 |
| T3 | 恢复 loopback 拒绝用例：credentialedURL/wrongPort/nonLoopbackHost/encodedTraversal + 构造期 https/user@/port-0 |

## 已删除（“如无必要，勿增实体”）
- `glass/ci/check-test-integrity.py`：正则扫源码的伪门禁（AGENTS §3.1 禁止），且步骤名自称 report-only 实为硬门禁
- `tools/check-doc-style.py`：永远绿的报告式 prose linter（656 命中无人处理）
- `glass/ci/test_rc1_recapture_matrix.py`：硬编码子串“对暗号”矩阵，且全部场景 report-only
- `glass/ci/test-assemble-resource-bundle.sh`：无任何 workflow 引用的孤儿
- `NativeModelDirectoryFailurePresentation.swift` + 测试：`groups`/`failures` 恒空的死展示层
- `LLMModelDTO`/`LLMModelGroupDTO`/`LLMModelFailureDTO`/`LLMModelsResponse`：无 authority 的死 DTO
- `RPCErrorDisposition` + 两个 `disposition` + 对应测试方法
- 对应 workflow 步骤（portable-checks 的 test-integrity/doc-style、native-ui 的 recapture matrix）
- `AGENTS.md` §5 清单同步更新为实际有效门禁

## 仍保留（经评估为合理，非垃圾）
- `NativeSessionStoreTests` 的 draft/竞态测试：使用 legacy seam，但断言真实行为（拒绝后保留草稿、切换取消等）
- `SessionRuntimeResilienceTests.testNormalStreamEndDoesNotReplayFollowWithinSameGeneration`：`session.follow` 正常结束不重放是刻意设计，且不清空 journal
- `CommandsController`/`SkillsController`：现被 `AuthenticatedHostFixtureTests` 用于校验 commands/skills 契约 DTO，保留为官方端点类型边界
- `official-ui-catalog.json` 仍为 b150a55：仓库无该历史 catalog 的再生器，`check-official-spec.py` 已显式标注为历史非运行时审计输入

## 最终验证
- `swift build --package-path glass`：0 警告 0 错误
- `swift test --package-path glass`：**476 tests / 27 skipped / 0 failures**
- 门禁全绿：remote-contract(54/57)、authenticated-host-fixtures、ghost-plane(8 selectors/26 slots)、official-locales、interaction-scenes、official-spec、runtime-asset-inventory、package-target-graph(±self-test)、ui-spec-build、theme-tokens、ci-workflow-layout、host-upgrade-report、markdown-links

---

# 第三轮：全项目大刀阔斧清理（如无必要，勿增实体）

## 结论先行
- Swift 代码量 **67,192 → 46,535 行（-31%）**；测试 **476 → 398**，全部通过。
- 删除 191 个文件、修改 110 个文件（`git status`）。

## 最大发现：整个插件平面是死代码
`GlassPluginPlane` 不在 app target 依赖图（`Package.swift` app deps = GlassCore/GlassSpec/GlassUI/GlassSnapshot），`import GlassPluginPlane` 在 Sources 中 0 处，`WKWebView` 在 app 中 0 处。因此全部 Ghost Plane 安全机制（CSP、loopback policy、response policy、activation gate、path traversal、MIME gate、temporary file store）**保护的是一个从未加载的 WebView**。
- 删除：`Sources/PluginPlane/`、`Sources/Core/Plugin/`、`Tests/PluginPlane/`、`Tests/Core/GhostPlane*`、`NativeUIManifestTests`、`OfficialGhostPlaneContractTests`、`SwiftAdapterRegistryTests`、`PluginRouteMatrixTests`、`NativeSchemaForm{,Draft}.swift` 及其测试、两个 JSON 资源。约 4,300 行。

## CI 官僚门禁全删
- 删除 3 个 workflow：`prepare-official-baseline.yml`（构建官方 TS monorepo，25 分钟超时）、`mutation-testing.yml`（唯一一次运行 90 分钟被取消）、`documentation-integrity.yml`。
- 删除 `portable-checks.yml`；`native-ui.yml` 重写为纯 `swift build` + `swift test`。
- 删除整个 `glass/ci/`（23 个脚本，含“重新生成官方 fixture 再与签入文件比对”的契约门禁、魔数 inventory、自测套娃）与 `tools/spec-generation/`、`tools/check-host-upgrade-report.py`、`tools/reference-capture/` 等。
- 仅保留：`swift build` / `swift test` / `tools/check-markdown-links.py` / `tools/emit-build-manifest.py` / `release.yml`。

## 安全/哈希表演删除
- 删除 `OfficialLocaleRuntimeCatalog` + 952 KB `official-locales.json`（仅测试读取，生产用编译期 `OfficialLocaleCatalog.swift`）。
- 删除 `OfficialAccessibilityBaseline` + JSON（仅测试读取）。
- 删除 `OfficialColumnLayoutFixtures` 的 commit/sha256/path 锁定与 `preconditionFailure`，保留 fixture 数值供布局数学测试。
- 删除 `OfficialUISpecBuild.swift` 的 4 个 sha256 revision、generatedAt、generatorVersion、requireCompatibility（无运行时读者）。
- 删除 `OfficialLocaleRuntimeCatalog` 等资源后，app bundle 减少约 1 MB 的测试/CI 专用 JSON。

## 垃圾测试与死代码
- `NativeSessionStoreTests.swift`：删除 19 个孤儿测试替身 + 6 个未用 helper（**2416 → 1292 行**，零覆盖损失）。
- 删除 4 个整文件镜像测试：`NativeCompactionPresentationTests`、`NativeJobsHeaderActionTests`、`NativeCredentialStatusPresentationTests`、`NativeTranscriptTailPresentationTests`。
- 删除 `OfficialUISpecBuildTests` 中 45 行 provenance 表演与两个已删 loader 的测试。
- 删除 49 个零引用 DTO（`RemoteDTOModels.swift` 39 个、`DomainAPIs.swift` 18 个，其中 8 个被活类型引用者已恢复）。
- 删除死属性 `GlassPolicy.ownsSystemNavigationMaterial` 与其测试。

## 文档/资产
- 删除 `TODO_LEGACY_RC2.md`（与 TODO.md 99.3% 重复）、`FIX_TODO.md`、`CONTINUOUS_EXECUTION_PLAN.md`、21 个零引用孤儿笔记、`docs/` 4 个孤儿文档、`visual-review/`、`design-reference/`、`build/icon.iconset/`。
- `AGENTS.md` §5 自检清单更新为 build/test/markdown-links；`CONTRIBUTING.md`、PR 模板重写以移除已删门禁引用。

## 那 40 个被删测试的结论
逐函数比对 `main` 与当前 `NativeSessionStoreTests`：被删的 57 个测试全部测的是**已整体移除的旧内部状态机**（`recoveryLiveBuffer`/`subscribedLastSequence`/`authorityRecovery`/`gapRecovery`/`residentResync`/`watermark` 在 main 有 19 处、现在 0 处），随代码删除是合理的，不应恢复。但其中“审批/提问接管、迟到回执不得改写新请求、队列失败作用域”等行为在新架构中仍有生产实现却零覆盖，值得后续用新 API 移植（`RemoteEventRuntime` + `SessionCommandService`）。

## 仍待下一轮
- ~~代码合并：重复的 tool-invocation reducer、JSON→Int 强转、locale 查找、loopback 校验、二分插入。~~ 见下节，均已处理或核实。
- ~~删除 legacy `TranscriptItem`/`items` 平行转录。~~ 已删除。
- ~~简化 `HostLogRedactor`（6 条正则）。~~ 已改为线性扫描。
- `docs/` 与 `notes/` 剩余历史文档的合并/删除（`notes/` 有 20 个零引用笔记，但多为进行中任务的来源映射，未动）。

---

# 第三轮续：全项目深度清理

## 本轮删除/简化
- **legacy 平行转录删除**：`NativeSessionStore.TranscriptItem`/`Role`/`@Published items`/`ResidentSessionState.items`/`settleStreaming`/`upsert`/`isOrdered`/`textContent`/`applyAssistantChunk` 全部移除，`apply(event:)` 只保留 queue/tool/isRunning 投影；12 处 `items = []` 与 2 处测试断言改为真正的 `chatNodes` 投影。源码 -190 行，App 内 `items` 读取者本就为 0。
- **`HostLogRedactor` 去正则**：6 条 `NSRegularExpression` + 预过滤 + `Rule` 结构（64 行）→ 单次线性扫描 + 字面量标记表（~70 行，无正则、无 `NSString` 桥接）；保留 T12.7 记录的 JSON 转义引号字段脱敏。测试改写为可证伪的脱敏/幂等断言。
- **loopback 校验收敛**：`HarnessHostController.announcedEndpoint`、`HostLaunchDescriptor.init`、`SessionLogExporter.isTrustedLoopbackDownloadURL` 三份重复规则收敛为 `URL.isCanonicalLoopbackHTTP`（HostLaunchDescriptor.swift）。
- **零引用 DTO 删除**：`RPCServerRequest`（自称“legacy test seam”，全仓零引用）、`QuestionAnswerBatch`、`QuestionResponsePayload`（private 且互引，无外部读者）。
- **`HostBuildVerifier`/`HostBuildClassifier` 保留**：核实 TODO.md T3.2 已 `[x]`、D5 明确为“版本兼容与社区宽容”交付项并有验收证据，不是死代码，未动。
- **移植有价值的行为测试**：为 `NativeSessionStore.updateQueuedMessage` 补 `testQueueActionFailureIsScopedToItsItemAndSuccessPublishesCompletion`（失败只落在触发项、成功发布 completion、请求精确 wire shape）——该生产路径此前零覆盖，对应被删旧测试里的“队列失败作用域”。审批/提问接管的接管与迟到回执已由 `InteractionCommandsRequireGenerationBoundResponder`、`RemoteInteractionProjectorTests` 及迟到接受类测试覆盖。

## 核实后判定“非垃圾”
- `NativeSessionLogExportOpener`（17 行）：T3.5 已 `[x]` 并文档化的 UI 侧导出 seam，当前无 shell 调用点，作为待接线 UI 边界保留，不当作死代码删除。
- `docs/` 7 个文档：`PLUGIN_COMPATIBILITY_PROPOSAL.md`（TODO 引用）、`REVIEW_PROTOCOL.md`、`VISUAL_REPLICATION_TEST_PLAN.md` 等均被 TODO/notes 引用。
- `glass/ci/test_rc1_recapture_matrix.py` 等源码级门禁：属进行中的视觉管线（T12.4/CUT1.8/POST5），虽为字符串对暗号写法，按“勿删在开发功能”原则保留。

## 本轮验证
- `swift build --package-path glass`：0 警告 0 错误。
- `swift test --package-path glass`：**461 tests / 27 skipped / 0 failures**。
- `python3 tools/check-markdown-links.py`：通过。
- 累计 `git diff HEAD`：137 files changed, 1219 insertions(+), 5411 deletions(-)；`glass/Sources` Swift 37,377 行。

---

# 第三轮修正：Ghost Plane 与视觉管线误删已回滚

## 错误
我按“app target 不依赖 GlassPluginPlane”判定整个插件平面是死代码并删除。**这是错误的**：TODO.md 明确把 Ghost Plane（GP-1~GP-5、T11.1~T11.8）列为**未完成的在开发功能**，`[ ]` 未勾选，进度记录写明“尚未接入 app”正是因为开发未到接入阶段。同理，视觉回归管线（`visual-scenes.json`/`visual-validation-policy.json`/`compare_visual_pair.py`/`prepare-official-baseline.yml`/`tools/reference-capture/`）对应 TODO 的未完成任务 T12.4 / CUT1.8 / POST5。

## 已回滚恢复
- `glass/Sources/PluginPlane/`、`glass/Sources/Core/Plugin/`、`glass/Tests/PluginPlane/`、全部 `GhostPlane*`/`NativeUIManifest`/`OfficialGhostPlaneContract`/`SwiftAdapterRegistry`/`PluginRouteMatrix` 测试、`NativeSchemaForm{,Draft}` 及其测试、两个 JSON 资源；Package.swift 的 `GlassPluginPlane` product/target/testTarget。
- `glass/ci/` 全部契约/视觉/资产门禁与 `tools/spec-generation/` 全部生成器与依赖声明、`tools/reference-capture/`、`glass/scripts/`、`visual-review/`、`design-reference/`、`notes/` 21 个笔记、`docs/` 4 个文档、Spec 下全部生成 catalog/JSON 与其 loader、`.github/workflows/{native-ui,portable-checks,prepare-official-baseline,documentation-integrity}.yml`。
- 重新应用第一轮对 Ghost Plane 的低风险修复：`GhostPlaneSkeleton` 两处强制解包、`OfficialGhostPlaneContract` 的 `sources.count >= 8`/`slots.count == 25` 魔数、`GhostPlaneLoopbackPolicyTests` 的安全拒绝用例。

## 仍然删除（用户明确点名的那类）
- `.github/workflows/mutation-testing.yml`（唯一一次运行 90 分钟被取消的突变分门禁）。
- `glass/ci/check-test-integrity.py`（正则扫项目 Swift 源码的伪门禁，AGENTS §3.1 明令禁止）。
- `glass/ci/test-ci-workflow-layout.py`（断言 YAML/Package.swift 字面量的“对暗号”门禁）。
- `tools/check-doc-style.py`（永远绿的报告式 prose linter）。
- `TODO_LEGACY_RC2.md`（与 TODO.md 99.3% 重复）、`FIX_TODO.md`（已被 REVIEW_FINDINGS 取代）、`CONTINUOUS_EXECUTION_PLAN.md`（过时 Manus 计划）。
- 4 个整文件镜像测试、`NativeModelDirectoryFailurePresentation` + 测试（恒空死展示层）。
- 代码层：`NativeSessionStoreTests` 的 19 个孤儿替身 + 6 个未用 helper（-1,100 行）、49 个零引用 DTO、`GlassPolicy.ownsSystemNavigationMaterial`、14 处 JSON→Int 强转已收敛为 `RemoteJSONValue.intValue/nonNegativeIntValue`。

## 教训
“当前未被 app 引用”不等于“死代码”。删除任何子系统前必须先查 TODO.md 的 `[ ]` 状态；开发中的功能即使尚未接线也必须保留。

---

# 附：AGENTS.md 重构（把守则变成可执行的硬约束）

## 诊断（旧版为什么没约束住模型）
1. 它是"历史错误图鉴"（14 条已命名反模式＋代码），不是决策程序；新类型的垃圾（死代码、零引用类型、镜像测试）不在清单里。
2. 完成定义只有 build/test/link，模型锁定"全绿"即可，垃圾照进。
3. 仓库自己违反 §14.3（仍存 6 个 `glass/ci/test-*.py|sh` 自测脚本），规则权威性归零。
4. 缺了最贵的护栏："删子系统前查 `TODO.md` `[ ]`"（Ghost Plane 误删教训）。
5. 机制级禁令（"禁止正则/哈希"）招致 whack-a-mole。

## 重构结果
- `AGENTS.md` 510 → 94 行：§0 红线 10 条、§1 默认立场"删 > 改 > 增"＋新增四问、§2 改动前决策门 5 问、§3 架构/并发红线、§4 完成定义（含死代码/测试/文档/规模自查）、§5 反模式速查表、§6 自审命令。
- 14 个详细 ❌/✅ 案例移入新增 `docs/ENGINEERING_CASEBOOK.md`（419 行，链接已改为 `../glass/...`），章程只留一行规则＋锚点链接。
- `python3 tools/check-markdown-links.py` 通过。

## 遗留一致性缺口（已按用户选择处理）
- 章程 §0.6 曾明令禁止所有"篡改 fixture → 跑子进程 → 断言错误字符串"的自测套娃，但仓库仍有 6 个此类脚本。按用户选择"改断言退出码 + 章程豁免"处理：
  - 删除错误文案断言：`glass/ci/test-official-ui-spec-build.py`（`"does not match Host catalog"`/`"metadata is stale"`）、`glass/ci/test-official-theme-tokens.py`（`"catalog is stale"`）、`glass/ci/test-package-target-graph.py`（三条 `"... internal dependencies" in failure` 子串断言 → 改为 `module.validate(...)` 非空）。
  - `test_visual_policy.py`/`test-assemble-resource-bundle.sh` 本就只断言退出码与结构化产物，未改。
  - `test_rc1_recapture_matrix.py` 是场景接线契约（读 JSON/TS/YAML，非 `.swift`、非门禁错误文案），不在本条禁令内，保留。
  - 章程 §0.6 改为："门禁自测允许篡改 fixture → 调用真实门禁 → 断言失败退出码或结构化产物；禁止断言门禁的错误文案。"
- 验证：`py_compile` 全通过；`test-package-target-graph.py`、`test_rc1_recapture_matrix.py`、`test_visual_policy.py` 本地实跑通过。
