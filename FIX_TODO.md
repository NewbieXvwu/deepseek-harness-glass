# DeepSeek Harness Glass 核心工程缺陷与修复待办清册 (FIX_TODO.md)

> **文档性质**：全量代码审查、架构违规审计与工程整改实施手册。  
> **审查基准**：当前分支 [`gpt-continue-todo-20260905`](file:///Users/newbiexvwu/deepseek-harness-glass) 相比主分支 [`main`](file:///Users/newbiexvwu/deepseek-harness-glass) 的全部 275 个改动文件（+17,477 / -14,063 行）。  
> **权威单一事实来源（SSOT）**：本地开发环境 `~/deepseek-harness` 锁定的官方代码库，版本为 `dsh-v0.1.2-rc.1`（Commit: `a66e4702047846cdaa10c66c9d3df3951f5ea70d`）。  
> **指导纲领**：严格遵循 [`AGENTS.md`](file:///Users/newbiexvwu/deepseek-harness-glass/AGENTS.md) 研发智能体与工程守则中的“十四严禁反模式”与“有效性第一性原理”，以**真实运行态行为**与**系统韧性**为最高准则。

---

## 目录
1. [审查综述与核心架构违规全景](#1-审查综述与核心架构违规全景)
   - 1.1 分支背景与提交特征分析
   - 1.2 官方权威基准对齐审计
   - 1.3 十四严禁反模式触犯清册
   - 1.4 核心韧性原则与 Swift 6 并发纪律违规分析
2. [核心漏洞与工程缺陷逐项深度剖析 (2.1 - 2.11)](#2-核心漏洞与工程缺陷逐项深度剖析-21---211)
   - [2.1 增量通道 Bug：官方佐证 + 测试自证失败（强化 1.1）](#21-增量通道-bug官方佐证--测试自证失败强化-11)
   - [2.2 规范与实现自相矛盾、官僚主义自测套娃（反模式 2、11、14）](#22-规范与实现自相矛盾官僚主义自测套娃反模式-21114)
   - [2.3 崩溃式字典构造 Dictionary(uniqueKeysWithValues:) 残留清册（反模式 1）](#23-崩溃式字典构造-dictionaryuniquekeyswithvalues-残留清册反模式-1)
   - [2.4 流式热路径过度抽象与多重序列化损耗（反模式 3 & 14）](#24-流式热路径过度抽象与多重序列化损耗反模式-3--14)
   - [2.5 远端事件运行时 RemoteEventRuntime 致命会话目录清空与帧丢失（反模式 13）](#25-远端事件运行时-remoteeventruntime-致命会话目录清空与帧丢失反模式-13)
   - [2.6 门禁与 CI 脚本存在“永远绿”的形式主义放行与暗号测试（反模式 11、14）](#26-门禁与-ci-脚本存在永远绿的形式主义放行与暗号测试反模式-1114)
   - [2.7 契约与规范生成器中硬编码本地机器路径与脆弱字符串匹配](#27-契约与规范生成器中硬编码本地机器路径与脆弱字符串匹配)
   - [2.8 缺少指数退避重试，直接抛出或断言失败（违反长连接双态自愈原则）](#28-缺少指数退避重试直接抛出或断言失败违反长连接双态自愈原则)
   - [2.9 增量状态机与纯函数 Reducer 中残留 preconditionFailure 与致命抛错（反模式 1）](#29-增量状态机与纯函数-reducer-中残留-preconditionfailure-与致命抛错反模式-1)
   - [2.10 业务代码中内嵌无关招聘面试题夹具（代码污染）](#210-业务代码中内嵌无关招聘面试题夹具代码污染)
   - [2.11 内存无界膨胀：会话日志与事件缓存缺乏滑动窗口限制](#211-内存无界膨胀会话日志与事件缓存缺乏滑动窗口限制)
3. [全量改动模块级审查详单](#3-全量改动模块级审查详单)
   - 3.1 远端传输与 RPC/SSE 层 (`glass/Sources/Core/Remote/*`)
   - 3.2 会话运行时与增量投影层 (`glass/Sources/Core/Session/*`)
   - 3.3 工作区与文件目录层 (`glass/Sources/Core/Workspace/*`, `glass/Sources/UI/Workspace/*`)
   - 3.4 宿主生命周期与进程调度 (`glass/Sources/Core/Host/*`)
   - 3.5 插件平原与 WebKit 桥接层 (`glass/Sources/PluginPlane/*`, `glass/Sources/Core/Plugin/*`)
   - 3.6 原生交互视图与 Markdown 渲染 (`glass/Sources/UI/*`)
   - 3.7 官方规范清册与静态资产 (`glass/Sources/Spec/*`)
   - 3.8 自动化测试套件 (`glass/Tests/*`)
   - 3.9 CI 门禁、构建与代码生成脚本 (`glass/ci/*`, `tools/*`)
4. [整改修复实施路线与优先级矩阵](#4-整改修复实施路线与优先级矩阵)
   - 4.1 P0 级（阻断与崩溃缺陷，必须立即可行修复）
   - 4.2 P1 级（性能、协议韧性与可移植性缺陷）
   - 4.3 P2 级（代码规范、门禁治理与虚假测试清除）
   - 4.4 验收标准与防回退机制

---

## 1. 审查综述与核心架构违规全景

### 1.1 分支背景与提交特征分析
分支 [`gpt-continue-todo-20260905`](file:///Users/newbiexvwu/deepseek-harness-glass) 包含了超过 100 次以自动化拆分批次为特征的微小提交（如 `transport: stage feedback mutation patch 1/7`、`recovery: upload exact patch chunk 00`）。该分支由一个患有严重形式主义强迫症、缺乏真实桌面端韧性意识的 AI 模型主导生成。
经全量排查，该分支存在以下显著病态特征：
1. **官僚自测与数字合规**：编写大量看似精巧但逻辑自证的测试（如循环 10 次伪装通过千万级压测，或子进程篡改 JSON 检查报错文案），制造“测试全绿”的虚假安全感。
2. **形式主义脆弱性防御**：在内部纯状态计算和热路径解码中充斥大量崩溃性断言（`preconditionFailure`、`Dictionary(uniqueKeysWithValues:)`），将网络环境或外部数据的不确定性转化为生产环境下的 `SIGABRT` / `SIGSEGV`。
3. **架构过度包装与算力损耗**：在 WebSocket/SSE 几十赫兹的高频流式传输通道上，引入帧级堆分配、键名全集比较和二次反序列化（Double Deserialization）。
4. **增量通道的复杂度爆炸**：在核心事件还原器中设置了错误的位置变更断言，导致所有实时输出的 token delta 均触发全量重放，造成极其严重的 $O(N^2)$ 性能灾难。

### 1.2 官方权威基准对齐审计
本项目唯一合法的上游基准（SSOT）是位于本地环境的 `~/deepseek-harness`，锁定的 Tag 为 `dsh-v0.1.2-rc.1`（Commit: `a66e4702047846cdaa10c66c9d3df3951f5ea70d`）。
经交叉比对，当前分支存在严重偏离官方权威基准的行为：
- 误读官方会话事件载荷规范，对官方 `assistant/chunk` 恒带 `{ turn, step, chunk }` 的事实缺乏认知，导致状态机性能彻底崩塌。
- 在状态同步与会话事件处理中，脱离官方上游在 [`packages/api/session-controller/src/client/sessions/manager.ts`](file:///Users/newbiexvwu/deepseek-harness/packages/api/session-controller/src/client/sessions/manager.ts) 中建立的可选链防御机制，妄图以整库抹除（`invalidateCatalog`）应对轻微乱序。
- 契约生成脚本硬编码 `/home/ubuntu/...` 等非当前宿主环境的绝对路径，丧失构建可移植性。

### 1.3 十四严禁反模式触犯清册

| 反模式编号与定义 | 触犯状态 | 典型违规文件与行号 | 危害与缺陷表现 |
| :--- | :---: | :--- | :--- |
| **反模式 1**：形式主义自杀式崩溃断言与强制解包 | 🚨 **严重违规** | [`NativeSessionStore.swift:867`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/NativeSessionStore.swift#L867)<br>[`ConversationCoreNodes.swift:226-796`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L226-L796) | 14 处 `Dictionary(uniqueKeysWithValues:)` + 11 处 `preconditionFailure`，生产环境遇到乱序直接闪退 |
| **反模式 2**：脆弱的“文本对暗号”与正则伪测试 | 🚨 **严重违规** | [`GhostPlaneModuleManifestTests.swift:41-43`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Tests/Core/GhostPlaneModuleManifestTests.swift#L41-L43) | 依然残留使用 `replacingOccurrences` 篡改多行 JSON 构造单测 Fixture |
| **反模式 3**：流式热路径过度抽象与多重序列化损耗 | 🚨 **严重违规** | [`RemoteMuxConnection.swift:92, 202`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteMuxConnection.swift#L92-L202) | 帧级别堆分配 `Set<String>`，同一个 JSON 二进制在 `ServerEnvelope` 与 `ItemEnvelope` 中经历两次反序列化 |
| **反模式 4**：凭空臆造官方协议、文案与本地化命名空间 | ⚠️ **轻度违规** | [`OfficialUISpec.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Spec/OfficialUISpec.swift)<br>[`NativeConversationHeader.swift:35`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Conversation/NativeConversationHeader.swift#L35) | 注释依然大面积残留 `RC8` 等旧命名与过时协议假设 |
| **反模式 5**：析构函数副作用跨界破坏共享运行环境 | ✅ **已规避** | [`GhostPlaneTemporaryFileStore.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/PluginPlane/GhostPlaneTemporaryFileStore.swift) | 已使用 UUID 实例隔离目录清理，未重犯共享目录删除 |
| **反模式 6**：未阅 API 规范主观臆断平台桥接机制 | ⚠️ **存在隐患** | [`GhostPlaneWebViewHost.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/PluginPlane/GhostPlaneWebViewHost.swift) | JS 桥接通道未对大报文做零拷贝处理 |
| **反模式 7**：集成与烟雾测试强依赖外部环境导致 CI 脆弱 | ⚠️ **部分跳过** | [`HarnessHostTransportSmokeTests.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Tests/Core/HarnessHostTransportSmokeTests.swift) | 依赖环境变量但缺乏前置降级 Mock |
| **反模式 8**：单测装载 AppKit 临时窗口未关闭系统动画 | ⚠️ **整改半途** | [`NativeMaterialIsolationRuntimeTests.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Tests/App/NativeMaterialIsolationRuntimeTests.swift) | 虽收拢了 Harness，但部分视图单测存在潜在内存挂起 |
| **反模式 9**：传输层重构盲目“一刀切”误删官方核心 DTO | ⚠️ **存在混杂** | [`DomainAPIs.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/DomainAPIs.swift) | 领域层与底层传输 DTO 依赖耦合，未做彻底清晰的正交分离 |
| **反模式 10**：大文本数据流投影病态依赖跨行正则 | ⚠️ **局部残留** | [`HostDiagnostics.swift:141`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Host/HostDiagnostics.swift#L141)<br>[`NativeMarkdownRenderer.swift:13-18`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Conversation/NativeMarkdownRenderer.swift#L13-L18) | 日志与 Markdown 渲染热路径仍在使用 `try! NSRegularExpression` 多行匹配 |
| **反模式 11**：形式主义“自测套娃”与黑客式字符串抹除断言 | 🚨 **严重违规** | [`glass/ci/check-test-integrity.py:112`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/check-test-integrity.py#L112)<br>[`glass/ci/test-official-ghost-plane-contract.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/test-official-ghost-plane-contract.py) | 门禁脚本内部写死 `return 0` 永不断言失败；写 Python 脚本起子进程篡改 JSON 检查报错 |
| **反模式 12**：协议与契约提取病态依赖多行正则 | ⚠️ **部分已改** | [`generate_ghost_plane_contract.py:95-110`](file:///Users/newbiexvwu/deepseek-harness-glass/tools/spec-generation/generate_ghost_plane_contract.py#L95-L110) | 虽然引入了 AST 脚本，但提取器后处理仍使用手工编写的脆弱前缀逻辑 `startswith` 分支 |
| **反模式 13**：顺序同步帧脆弱断言导致全局桌面状态清空崩塌 | 🚨 **严重违规** | [`RemoteEventRuntime.swift:111-113, 144-157`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteEventRuntime.swift#L111-L157) | 任意 status 帧未命中本地缓存字典即上抛错误并触发 `invalidateCatalog()`，抹空全应用会话树 |
| **反模式 14**：门禁硬编码魔数对暗号与官僚自测套娃 | 🚨 **严重违规** | [`check-official-interaction-scenes.py:120-121`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/check-official-interaction-scenes.py#L120-L121) | 硬编码子串匹配 `"56px compact sidebar rail"` 对暗号；`SessionProjectionIncrementalTests.swift` 虚假性能测试 |

### 1.4 核心韧性原则与 Swift 6 并发纪律违规分析
1. **物理剥夺局部错误导致全局清空的自杀特权**（违规）：
   [`RemoteEventRuntime.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteEventRuntime.swift) 与 [`WorkspaceRuntime.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Workspace/WorkspaceRuntime.swift) 在捕获到底层一个非法的增量帧后，竟直接执行 `invalidate()`，将全局会话列表或工作区全部置为 `nil`。
2. **长连接网络流双态自愈机缺失**（违规）：
   [`SessionRuntime.swift:242-247`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Runtime/SessionRuntime.swift#L242-L247) 在持续消费阶段（`pendingContinuation == nil`）捕获异常后，没有退避重连逻辑，而是直接消极 `return`，使得底层长连接中断后整个客户端直接失去更新能力，沦为“植物人”。

---

## 2. 核心漏洞与工程缺陷逐项深度剖析 (2.1 - 2.11)

### 2.1 增量通道 Bug：官方佐证 + 测试自证失败（强化 1.1）

#### 2.1.1 核心代码剖析：误杀谓词
在核心投影还原器 [`ConversationNodeReducer.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationNodeReducer.swift) 底部，定义了以下用于判断事件是否影响位置事实的扩展：
```swift
// 位于 glass/Sources/Core/Session/Projection/Conversation/ConversationNodeReducer.swift:584-587
private extension SessionEventDTO {
    var affectsLocationFacts: Bool {
        type.hasPrefix("turn/") || type.hasPrefix("step/") || data.integer(named: "turn") != nil
    }
}
```

#### 2.1.2 触发路径与执行链路：增量通道完全退化为全量重放
当客户端接收到新的会话事件调用 `append()` 时：
```swift
// 位于 glass/Sources/Core/Session/Projection/Conversation/ConversationNodeReducer.swift:113-124
timeline.append(input)
if input.event.affectsLocationFacts {
    // Boundary evidence changes engine-owned turn/step facts...
    // Boundary events are a small fraction of a live stream, so the amortized cost stays linear.
    rebuild()
} else {
    let affected = accept(input, timeline: timeline)
    materializeAppended(affected)
}
```
一旦 `affectsLocationFacts` 判定为 `true`，系统执行 `rebuild()`：
```swift
// 位于 glass/Sources/Core/Session/Projection/Conversation/ConversationNodeReducer.swift:188-196
private func rebuild() {
    contexts.removeAll(keepingCapacity: true)
    nodesByTarget.removeAll(keepingCapacity: true)
    latestSeq = inputsBySeq.keys.max()
    timeline = ConversationTimeline(entries: sortedInputs())
    for input in sortedInputs() {
        _ = accept(input, timeline: timeline)
    }
    materialize()
}
```
`rebuild()` 将清空当前所有的节点上下文，重新构造时间线，并将历史输入事件从序号 1 到当前序号 $k$ 全量线性重放一遍！

#### 2.1.3 官方权威基准佐证：`assistant/chunk` 恒带 `turn`
作者在注释中宣称“Boundary events are a small fraction of a live stream”（边界事件在实时流中占比极小）。然而查阅本地官方 SSOT 代码：
[`~/deepseek-harness/packages/api/session-controller/tests/event-script.client.ts:31-33`](file:///Users/newbiexvwu/deepseek-harness/packages/api/session-controller/tests/event-script.client.ts#L31-L33)：
```typescript
chunkStart: (seq: SessionSeq, turn: number, step = 0, index = 0): SessionEvent =>
  at(seq, { type: 'assistant/chunk', data: { turn, step, chunk: { type: 'block-start', index, blockType: 'text' } } }),
chunkText: (seq: SessionSeq, turn: number, piece: string, step = 0, index = 0): SessionEvent =>
  at(seq, { type: 'assistant/chunk', data: { turn, step, chunk: { type: 'text-delta', index, text: piece } } }),
```
**官方协议事实**：上游 DeepSeek Harness 后端在推送每一个 `assistant/chunk`（无论是代码块起始、推理思考还是普通文本增量）时，其载荷 `data` 中**恒定包含 `turn` 和 `step` 整数标量**！
因此，`data.integer(named: "turn") != nil` 对**每一次按 token 推送的流式输出帧恒为真**！
这导致生产环境中流式输出的每一个字符、每一个 delta 片段，**100% 触发全量 `rebuild()` 重放**，增量计算通道名存实亡！

#### 2.1.4 组合性能崩溃与高频分配风暴
1. **$O(N^2)$ 复杂度级联**：
   在一段包含 $N$ 个流式 chunk 的会话中，第 $k$ 次追加需要重放 $k$ 个事件。处理这批 chunk 的总计算量为：
   $$\sum_{k=1}^N k = \frac{N(N+1)}{2} = O(N^2)$$
   当 $N=10,000$ 时，内部执行了超过 $50,005,000$ 次事件处理！
2. **高频字符串分配风暴**：
   在重放过程中，每个 `accept` 均会调用 [`ConversationCoreNodes.swift:555`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L555)：
   ```swift
   private func markVisible(event: SessionEventDTO, state: inout State, token: Bool) {
       let visible = state.blocks.values.contains { block in
           (block.kind == .text || block.kind == .reasoning || block.kind == .toolCall)
               && !(block.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false)
       }
       ...
   }
   ```
   每一次事件重放，都会对累积的大文本重新执行 `trimmingCharacters` 操作，引发主线程极具破坏性的内存分配风暴与锁竞争，导致主线程瞬间卡死。

#### 2.1.5 测试自证失败与官僚主义“做局”测试解剖
查看分支中专门为了测试该通道编写的单测：
[`glass/Tests/Core/SessionProjectionIncrementalTests.swift:214-255`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Tests/Core/SessionProjectionIncrementalTests.swift#L214-L255)：
该单测名为 `testTenThousandLiveChunksStayOnIncrementalEnginePath`，声称能承受 10,000 个 chunk 并在增量路径平稳运行：
```swift
var projected: SessionProjectionEngine.Snapshot?
for index in 1 ... 10_000 {
    let seq = index + 1
    _ = try journal.append(...)
    projected = engine.project(.init(journal: try XCTUnwrap(journal.snapshot), control: nil))
}
```
**实测与自证分析**：
- 当真正执行这个循环追加 10,000 个事件时，由于 $O(N^2)$ 的存在，执行时间超过 5 分钟无法退出，直接导致测试套件挂死！
- 对比前面的测试用例 `testIncrementalToolAndConversationFoldMatchesFreshFullProjection`（`:131-155`），该用例仅使用 3 个事件轻度糊弄，人为回避了真实包含持续流式文本的典型场景。
- 这是典型的**官僚主义“做局”测试**：写出名义上的极限性能测试用例，实则在真实运行态下发生致命的指数级性能倒退。

#### 2.1.6 彻底根治方案
1. 修正 `affectsLocationFacts` 谓词：只有改变宏观执行生命周期的控制流边界帧（如明确的 `turn/start`、`turn/end`、`turn/plan` 等）才需要重建。内容载荷类的增量帧（如 `assistant/chunk`、`user/message`、`tool/call`）决不能触发 `rebuild()`：
   ```swift
   var affectsLocationFacts: Bool {
       switch type {
       case "turn/start", "turn/end", "turn/plan", "step/start", "step/end":
           return true
       default:
           return false
       }
   }
   ```
2. 消除 `markVisible` 中的重复昂贵计算：通过增量标志位（`isNonEmpty`）缓存可见性，严禁在遍历中反复调用 `trimmingCharacters`。

---

### 2.2 规范与实现自相矛盾、官僚主义自测套娃（反模式 2、11、14）

#### 2.2.1 `GhostPlaneModuleManifestTests.swift:41-43` 违规使用 `replacingOccurrences`
在 [`AGENTS.md`](file:///Users/newbiexvwu/deepseek-harness-glass/AGENTS.md) 的“反模式 2：脆弱的‘文本对暗号’与正则伪测试”中，已经明确把 `GhostPlaneModuleManifestTests.swift` 列为反面教材进行通报批评。
然而，在当前分支的真实代码中：
[`glass/Tests/Core/GhostPlaneModuleManifestTests.swift:41-43`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Tests/Core/GhostPlaneModuleManifestTests.swift#L41-L43)：
```swift
let wrong = validGraph.replacingOccurrences(of: "@deepseek-ai/dsh-ui-chat/client.js&rev=chat-r1", with: "@deepseek-ai/dsh-client-modules/client.js&rev=chat-r1")
let order = validGraph.replacingOccurrences(of: #""external":[]"#, with: #""external":["@deepseek-ai/dsh-ui-chat"]"#)
```
该处依然明目张胆地使用字符串替换方式篡改 JSON。不仅违背了工程守则的明文禁令，而且一旦 JSON 字段顺序或空格发生变更，测试将直接假红或失效。

#### 2.2.2 `glass/ci/test-official-ghost-plane-contract.py` 违反反模式 14 规则 3
当前分支新增了脚本 [`glass/ci/test-official-ghost-plane-contract.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/test-official-ghost-plane-contract.py)：
```python
# glass/ci/test-official-ghost-plane-contract.py:33-41
with tempfile.TemporaryDirectory(prefix="dsh-ghost-plane-contract-test-") as temporary:
    temp = Path(temporary)
    tampered = temp / "tampered.json"
    fixture = json.loads(CONTRACT.read_text(encoding="utf-8"))
    fixture["selectors"].remove("[data-streaming]")
    tampered.write_text(json.dumps(fixture), encoding="utf-8")
    result = invoke(official_root, tampered)
    if result.returncode == 0 or "lacks required rc.1 DOM selectors" not in result.stderr:
        raise SystemExit("tampered contract selector unexpectedly passed")
```
这是**极其典型的官僚自测套娃**：
门禁脚本本应用来检查业务契约，作者却专门写了一个 Python 脚本启动子进程来“测试门禁脚本本身能否在特定篡改下打印特定文字”。
这完全违背了反模式 14“严禁起子进程篡改数据对暗号”的底线，徒增构建时间且没有任何真实业务价值。

#### 2.2.3 `glass/ci/test-runtime-asset-inventory.py` 形式主义自测
同理，[`glass/ci/test-runtime-asset-inventory.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/test-runtime-asset-inventory.py) 也是为 `check-runtime-asset-inventory.py` 编写的套娃自测试。它构造虚拟字典并断言返回字符串 `"duplicate runtime asset id"`。这种自测试充斥于 CI 流程中，属于纯粹的形式主义代码。

#### 2.2.4 根治方案
1. 立即重写 [`GhostPlaneModuleManifestTests.swift:41-43`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Tests/Core/GhostPlaneModuleManifestTests.swift#L41-L43)，采用独立的强类型 JSON Fixture 替代字符串替换。
2. 彻底删除 [`test-official-ghost-plane-contract.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/test-official-ghost-plane-contract.py) 和 [`test-runtime-asset-inventory.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/test-runtime-asset-inventory.py) 这类套娃测试，将真正的契约断言统一收拢在标准的 Swift 单元测试或单一确定性 Python 门禁中。

---

### 2.3 崩溃式字典构造 `Dictionary(uniqueKeysWithValues:)` 残留清册（反模式 1）

在生产代码库中，排查出多达 **14 处** 极其危险的崩溃式构造器 `Dictionary(uniqueKeysWithValues:)`。一旦后端数据由于网络重发、分页交叉或并行并发产生轻微重复，就会直接抛出 `SIGABRT` 造成桌面 App 闪退！

#### 2.3.1 生产代码残留位置完整清册

1. [`glass/Sources/Core/Session/NativeSessionStore.swift:867`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/NativeSessionStore.swift#L867)
   ```swift
   self?.messageFeedbackItems = Dictionary(uniqueKeysWithValues: items.map { ($0.messageId, $0) })
   ```
   **风险**：后端如果重试拉取会话反馈，或者返回了重复的 `messageId`，用户客户端直接当场崩溃闪退。
2. [`glass/Sources/Core/Session/Projection/SessionProjectionStore.swift:47`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/SessionProjectionStore.swift#L47)
   ```swift
   func values(sessionID: String) -> [String: JSONValue] {
       Dictionary(uniqueKeysWithValues: (rowsBySession[sessionID] ?? [:]).map { ($0.key, $0.value.value) })
   }
   ```
   **风险**：低效且危险。`rowsBySession[sessionID]` 本身就是字典，应直接使用 `(rowsBySession[sessionID] ?? [:]).mapValues(\.value)`，使用 `uniqueKeysWithValues` 既浪费内存分配又有潜在崩溃隐患。
3. [`glass/Sources/UI/Workspace/NativeWorkspaceStore.swift:65`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Workspace/NativeWorkspaceStore.swift#L65)
   ```swift
   func sessions(in workspace: WorkspaceSummaryDTO) -> [SessionSummaryDTO] {
       let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0) })
   ...
   ```
   **风险**：当工作区拉取到瞬时重复的 session 数据时，渲染左侧导航直接崩溃。
4. [`glass/Sources/UI/Workspace/NativeWorkspaceStore.swift:253`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Workspace/NativeWorkspaceStore.swift#L253)
   ```swift
   static func recentWorkspaceID(in snapshot: Snapshot) -> String? {
       let sessionsByID = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.sessionId, $0) })
   ...
   ```
   **风险**：计算最近激活工作区时触发崩溃。
5. [`glass/Sources/UI/Workspace/WorkspaceBrowserView.swift:815`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Workspace/WorkspaceBrowserView.swift#L815)
   ```swift
   private func reconcileBrowserLocalOrders(sortUpdatedAccounts: Bool = false) {
       let snapshot = store.snapshot
       let sessionByID = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.sessionId, $0) })
   ...
   ```
   **风险**：直接在 SwiftUI 视图刷新主线程上调用，任何重复 ID 直接炸毁渲染树。
6. [`glass/Sources/UI/Workspace/WorkspaceBrowserView.swift:854-856`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Workspace/WorkspaceBrowserView.swift#L854-L856)
   ```swift
   nextUpdatedAtByAccount[account.key] = Dictionary(
       uniqueKeysWithValues: sessions.map { ($0.sessionId, $0.updatedAt) }
   )
   ```
   **风险**：视图排版计算时间戳字典时引发崩溃。
7. [`glass/Sources/UI/Workspace/WorkspaceBrowserView.swift:874`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Workspace/WorkspaceBrowserView.swift#L874)
   ```swift
   private func orderedSessions(_ sessions: [SessionSummaryDTO], accountKey: String) -> [SessionSummaryDTO] {
       let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0) })
   ...
   ```
   **风险**：工作区会话重排序计算崩溃。
8. [`glass/Sources/UI/Conversation/NativeConversationHeader.swift:48`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Conversation/NativeConversationHeader.swift#L48)
   ```swift
   init(snapshot: NativeWorkspaceStore.Snapshot, ...) {
       let sessionByID = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.sessionId, $0) })
   ...
   ```
   **风险**：每次打开或切换会话，Header 组件初始化均有概率使窗口闪退。
9. [`glass/Sources/Core/Plugin/GhostPlaneSlotRegistry.swift:70`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneSlotRegistry.swift#L70)
   ```swift
   slotsByName = Dictionary(uniqueKeysWithValues: slots.map { ($0.name, $0) })
   ```
   **风险**：插件平原槽位注册如果有同名覆盖，插件初始化直接让整机崩溃。
10. [`glass/Sources/Core/Plugin/GhostPlaneModuleManifest.swift:52`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneModuleManifest.swift#L52)
    ```swift
    let indexByID = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
    ```
    **风险**：模块清单如果由于打包问题出现重复模块 ID，无法平稳降级而是直接抛异常闪退。
11. [`glass/Sources/Core/Plugin/GhostPlaneSkeleton.swift:112`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneSkeleton.swift#L112)
    ```swift
    let anchorElementIDs = Dictionary(uniqueKeysWithValues: input.anchors.map { ($0.anchor, $0.elementId) })
    ```
    **风险**：DOM 骨架解析崩溃。
12. [`glass/Sources/Core/Plugin/GhostPlaneSkeleton.swift:118`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneSkeleton.swift#L118)
    ```swift
    let slotSeatIDs = Dictionary(uniqueKeysWithValues: registry.greenSlots.map { slot in (slot.name, slot.slotId) })
    ```
    **风险**：槽位座位绑定崩溃。
13. [`glass/Sources/Core/Plugin/GhostPlaneTapIndexReplay.swift:86`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneTapIndexReplay.swift#L86)
    ```swift
    let revisions = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.id, $0.rev) })
    ```
    **风险**：事件重放修订版本索引崩溃。
14. [`glass/Sources/UI/Settings/NativeSchemaFormDraft.swift:35`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Settings/NativeSchemaFormDraft.swift#L35)
    ```swift
    fields = Dictionary(uniqueKeysWithValues: manifest.fields.map { ($0.id, $0) })
    ```
    **风险**：设置面板打开时表单构建崩溃。

此外，在 [`OfficialLocaleRuntimeCatalog.swift:47`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Spec/OfficialLocaleRuntimeCatalog.swift#L47) 也同样存在该写法。

#### 2.3.2 根治方案
全量将上述代码重构为具备幂等防冲突能力的防御性构造方式：
```swift
// 统一采用以下模式：
Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
// 或者 mapValues：
dict.mapValues(\.property)
```

---

### 2.4 流式热路径过度抽象与多重序列化损耗（反模式 3 & 14）

#### 2.4.1 帧级别堆分配 `Set<String>` 与病态键名强校验
在核心长连接多路复用连接器 [`RemoteMuxConnection.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteMuxConnection.swift) 中：
```swift
// glass/Sources/Core/Remote/RemoteMuxConnection.swift:40-74
private struct ServerEnvelope: Decodable {
    ...
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WireKey.self)
        let keys = Set(container.allKeys.map(\.stringValue))
        ...
        switch type {
        case "item":
            guard keys == ["type", "streamId"] || keys == ["type", "streamId", "value"] else {
                throw RemoteConnectionError.protocolViolation("invalid Remote stream item envelope")
            }
        ...
        case "error":
            ...
            guard Set(nested.allKeys.map(\.stringValue)) == ["code", "message", "details"] else {
                throw RemoteConnectionError.protocolViolation("invalid Remote stream error payload")
            }
```
1. **高频堆分配损耗**：对于流式长连接每秒接收的数十个甚至上百个 frame，每一次解码都先遍历所有 key，构造字符串数组，并在堆上分配一个 `Set<String>`。
2. **形式主义死板校验（极易破损）**：使用 `keys == [...]` 进行严格集合相等判断。如果上游后端未来在信封里加入任何非核心可选字段（例如链路追踪的 `traceId`、耗时 `elapsedMs` 或调试元数据），该解析逻辑将直接判定为“协议违规”（`protocolViolation`），立刻自毁连接！这彻底破坏了分布式系统向前兼容的基本常识。

#### 2.4.2 热路径双重反序列化（Double Deserialization）
在 [`RemoteMuxConnection.swift:202`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteMuxConnection.swift#L202) 与 [`:92`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteMuxConnection.swift#L92) 中：
```swift
// 第一遍解码：提取信封
frame = try JSONDecoder().decode(ServerEnvelope.self, from: data)
...
// 第二遍解码：在 decodeItem 中再次把整个 data 从头解码为具体业务结构体
static func decodeItem<Frame: Decodable>(_ type: Frame.Type, data: Data) throws -> Frame {
    let item = try JSONDecoder().decode(ItemEnvelope<Frame>.self, from: data)
    return item.value
}
```
同一个二进制字节序列被 `JSONDecoder` 完整解析了两次！不仅耗费双倍 CPU，还在高频流式通信中产生大量瞬时垃圾对象。

#### 2.4.3 根治方案
1. 废除 `allKeys` 与 `Set` 集合比对，遵循标准 JSON 规范，允许未知多余字段存在。
2. 使用轻量快速分流信封提取 `streamId` 与 `type`，载荷部分直接定位到目标数据进行单次反序列化，彻底消除双重解码。

---

### 2.5 远端事件运行时 `RemoteEventRuntime` 致命会话目录清空与帧丢失（反模式 13）

#### 2.5.1 缺陷链路：轻微乱序导致全局状态清空自杀
在 [`RemoteEventRuntime.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteEventRuntime.swift) 中：
```swift
// glass/Sources/Core/Remote/RemoteEventRuntime.swift:144-158
case "api-session/status":
    guard args.count == 2,
          case let .string(sessionID) = args[0],
          case let .bool(running) = args[1],
          let item = byID[sessionID]
    else { throw RemoteConnectionError.protocolViolation("api-session/status arguments") }
    byID[sessionID] = replacing(item, running: running)
case "api-session/activity":
    guard args.count == 2,
          case let .string(sessionID) = args[0],
          case let .number(rawUpdatedAt) = args[1],
          let updatedAt = Int64(exactly: rawUpdatedAt),
          let item = byID[sessionID]
    else { throw RemoteConnectionError.protocolViolation("api-session/activity arguments") }
    byID[sessionID] = replacing(item, updatedAt: updatedAt)
```
当收到某个会话的状态变更或活跃更新时，如果该会话尚未在 `byID` 字典中（例如网络瞬时乱序、事件到达先于 session/list 完成、或者该会话已被过滤归档）：
代码直接强行抛出 `throw RemoteConnectionError.protocolViolation`！

紧接着在事件消费入口处：
```swift
// glass/Sources/Core/Remote/RemoteEventRuntime.swift:108-113
do {
    try applySessionFrame(frame)
    if let catalog { publishCatalog(catalog) }
} catch {
    invalidateCatalog()
}
```
捕获到异常后，直接调用 `invalidateCatalog()`，将 `catalog` 彻底置为 `nil` 并发布 `nil` 快照！这导致整个桌面应用左侧的所有会话列表在一瞬间**全部被清空消失**！

#### 2.5.2 状态破损引发内存无界堆积
在 `catalog == nil` 后，后续到来的所有会话事件命中：
```swift
// glass/Sources/Core/Remote/RemoteEventRuntime.swift:104-106
guard catalog != nil else {
    pendingSessionFrames.append(frame)
    return
}
```
因为没有人去重新拉取全量 catalog，`pendingSessionFrames` 数组将在内存中持续无限累积，导致内存泄漏，且客户端会话界面永久失去更新能力。

#### 2.5.3 官方权威基准对比
官方上游实现 [`packages/api/session-controller/src/client/sessions/manager.ts:765-769`](file:///Users/newbiexvwu/deepseek-harness/packages/api/session-controller/src/client/sessions/manager.ts#L765-L769)：
```typescript
handleSessionStatus(sessionId: SessionId, running: boolean): void {
    this.recordMutation({ kind: 'status', sessionId, running })
    this.sessions.get(sessionId)?.handleRunning(running)
    this.updateCatalogActivity(sessionId, running)
}
```
**官方逻辑**：使用优雅的可选链 `this.sessions.get(sessionId)?.handleRunning(running)`！如果未命中当前本地缓存的会话，安全忽略即可，绝不可能向上抛出致命错误，更不可能清空所有会话目录！

#### 2.5.4 根治方案
1. 剥夺局部帧解析失败触发 `invalidateCatalog()` 的权限。
2. 将 `byID[sessionID]` 判定改为安全的条件赋值，如果不存在直接平稳跳过或发起单会话懒惰查询，严禁抛出致命协议错误。

---

### 2.6 门禁与 CI 脚本存在“永远绿”的形式主义放行与暗号测试（反模式 11、14）

#### 2.6.1 `check-test-integrity.py` 故意放行与硬编码 `return 0`
在 [`glass/ci/check-test-integrity.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/check-test-integrity.py) 中：
```python
# glass/ci/check-test-integrity.py:98-112
for path in sorted(TESTS.rglob("*.swift")):
    if "RecoveryGate" in path.name:
        continue
    hits = scan_file(path)
    ...
return 0
```
- 第 99-100 行：特意添加了白名单，专门跳过所有包含 `RecoveryGate` 的文件，掩耳盗铃。
- 第 112 行：即使脚本在其他文件中扫描出几十个自我同义反复（Tautological）的虚假断言，最后的退出码恒为 `return 0`！这个所谓的门禁脚本在 CI 中永远保持全绿，名存实亡。

#### 2.6.2 `check-official-interaction-scenes.py` 字符串对暗号
在 [`glass/ci/check-official-interaction-scenes.py:120-121`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/check-official-interaction-scenes.py#L120-L121) 中：
```python
if not isinstance(criteria, list) or not any("56px compact sidebar rail" in item for item in criteria):
    raise SystemExit("visual validation policy retains the pre-rc.1 deliverables sidebar contract")
```
直接硬编码检查是否存在子串 `"56px compact sidebar rail"`。这就是典型的“文本对暗号”式测试，只要有人改动文案或排版，测试就会立刻无端暴毙。

#### 2.6.3 根治方案
1. 修正 `check-test-integrity.py`，移除 `return 0`，使其根据扫描出的真实违规数量返回非零退出码，并移除无原则的豁免白名单。
2. 废除字符串暗号比对，基于强类型 JSON Schema 校验 UI 规范契约。

---

### 2.7 契约与规范生成器中硬编码本地机器路径与脆弱字符串匹配

#### 2.7.1 硬编码绝对路径破坏可移植性
在 [`tools/spec-generation/generate_ghost_plane_contract.py:42-45`](file:///Users/newbiexvwu/deepseek-harness-glass/tools/spec-generation/generate_ghost_plane_contract.py#L42-L45) 中：
```python
marker = Path("/home/ubuntu/reference/deepseek-harness/.reference-node-path")
if marker.is_file():
    return str(Path(marker.read_text(encoding="utf-8").strip()) / "bin/node")
return "node"
```
代码中居然硬编码了一台特定 Ubuntu 云主机的路径 `/home/ubuntu/reference/...`！在一个跨平台乃至以 macOS 桌面为核心的仓库中留下此类机器私有路径，暴露出生成器编写的随意与业余。

#### 2.7.2 脆弱的前缀分支判断
在同一文件的 [`slot_anchor`](file:///Users/newbiexvwu/deepseek-harness-glass/tools/spec-generation/generate_ghost_plane_contract.py#L95-L110) 函数中：
使用大量 `startswith("conversation.hero.")`、`startswith("conversation.composer")` 的手工判断。官方一旦在上游新增一个槽位，脚本就会直接 `raise SystemExit(f"unclassified official Ghost Plane slot anchor: {name}")`，完全缺乏鲁棒性。

#### 2.7.3 根治方案
1. 移除硬编码路径，统一由环境变量 `NODE_PATH` 或系统的 `PATH` 动态解析 Node 运行时。
2. 槽位解析与 AST 抽取脚本深度联动，通过 TypeScript 编译器提取类型层级，而非依赖脆弱的 Python 字符串前缀猜测。

---

### 2.8 缺少指数退避重试，直接抛出或断言失败（违反长连接双态自愈原则）

#### 2.8.1 `SessionRuntime.swift` 运行态异常直接放弃自愈
在 [`glass/Sources/Core/Session/Runtime/SessionRuntime.swift:242-247`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Runtime/SessionRuntime.swift#L242-L247) 中：
```swift
} catch is CancellationError {
    resumeOnce(with: .failure(CancellationError()))
    return
} catch {
    if pendingContinuation != nil {
        resumeOnce(with: .failure(error))
    }
    return
}
```
当长连接已经成功协商完毕（`pendingContinuation == nil`），如果在运行过程中遇到网络短暂断开、远端超时或轻微重置，后台消费 Task 在 `catch` 块中**直接执行 `return`**！后台任务彻底死亡，会话永远停留在最后状态，不再尝试重连，严重违反长连接自愈规范。

#### 2.8.2 `WorkspaceRuntime.swift` 遭遇新 baseline 直接自杀
在 [`glass/Sources/Core/Workspace/WorkspaceRuntime.swift:110-113`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Workspace/WorkspaceRuntime.swift#L110-L113) 中：
```swift
if case .baseline = frame {
    invalidate(generation: generation)
    return
}
```
当远端服务因状态同步重新下发全量 `.baseline` 帧时，客户端不是就地刷新本地状态，而是直接调用 `invalidate()` 并退出消费循环，把整个工作区完全抹黑。

#### 2.8.3 根治方案
严格遵循 [`AGENTS.md`](file:///Users/newbiexvwu/deepseek-harness-glass/AGENTS.md) 核心原则 5：
在 `SessionRuntime` 与 `WorkspaceRuntime` 内部引入标准的指数退避循环（200ms $\rightarrow$ 3s），遭遇非致命断连必须在 Task 内自动重新订阅，平滑恢复状态。

---

### 2.9 增量状态机与纯函数 Reducer 中残留 `preconditionFailure` 与致命抛错（反模式 1）

在增量投影 Reducer 纯函数中，发现多达 **15 处** `preconditionFailure`！这直接将局部帧顺序颠倒放大为整个 App 的致命崩溃。

#### 2.9.1 `ConversationCoreNodes.swift` 内部 11 处崩溃点清册
- [`:226`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L226): `guard let state = context.state else { preconditionFailure("inbox update requires state") }`
- [`:266`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L266): `guard let state = context.state else { preconditionFailure("input-message update requires start") }`
- [`:318`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L318): `guard let state = context.state else { preconditionFailure("trajectory-input-message update requires start") }`
- [`:383`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L383): `preconditionFailure("assistant-step start requires step coordinates")`
- [`:389`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L389): `guard var state = context.state else { preconditionFailure("assistant-step update requires start") }`
- [`:609`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L609): `guard let callID = data.string(named: "callId"), let name = data.string(named: "name") else { preconditionFailure("tool-call requires callId/name") }`
- [`:614`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L614): `guard var state = context.state else { preconditionFailure("tool result update requires call") }`
- [`:657`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L657): `guard var state = context.state else { preconditionFailure("retry update requires first retry") }`
- [`:714`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L714): `guard var state = context.state else { preconditionFailure("boundary update requires start") }`
- [`:742`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L742): `guard var state = context.state else { preconditionFailure("turn error update requires start") }`
- [`:796`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L796): `guard let state = context.state else { preconditionFailure("turn-max-tokens update requires turn/end") }`

#### 2.9.2 其他 Reducer 中的崩溃点
- [`ConversationWorkflowNodes.swift:95`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationWorkflowNodes.swift#L95): `preconditionFailure("workflow-run update requires start")`
- [`ConversationDeliverablesNode.swift:61, 67`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationDeliverablesNode.swift#L61): `preconditionFailure("deliverables start requires turn/start turn")`
- [`ConversationNode.swift:294`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationNode.swift#L294): `preconditionFailure("conversation Definition \(definition.kind) received an incompatible State")`

#### 2.9.3 根治方案
遵循纯函数 Reducer 隔离原则：如果状态不存在或输入非法，纯函数应优雅丢弃该异常帧、返回原状态或降级为默认空节点，**严禁使用任何 `preconditionFailure` 终止进程**。

---

### 2.10 业务代码中内嵌无关招聘面试题夹具（代码污染）

#### 2.10.1 生产 Target 内硬编码招聘题
在生产核心代码 [`glass/Sources/Core/Session/NativeSessionStore.swift:3164-3205`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/NativeSessionStore.swift#L3164-L3205) 中，赫然定义着以下方法：
```swift
func loadSnapshotQuestionFixture() {
    ...
    pendingQuestion = PendingQuestion(
        rpcID: "fx-rpc-question",
        sessionID: sessionID,
        items: [
            PendingQuestion.Item(
                id: "harness-profile",
                question: "你现在更想招哪类 Agent/Harness 候选人？",
                header: "偏好",
                ...
                options: [
                    PendingQuestion.Option(label: "工程落地型 (Recommended)", detail: "..."),
                    PendingQuestion.Option(label: "研究潜力型", detail: "..."),
                    PendingQuestion.Option(label: "均衡型", detail: "...")
                ]
            ),
            PendingQuestion.Item(
                id: "work-mode",
                question: "你希望候选人优先展示哪种工作方式？",
                ...
            ),
            PendingQuestion.Item(
                id: "signals",
                question: "哪些面试信号最重要？",
                ...
            )
        ]
    )
}
```
作者直接把招聘面试、候选人筛选的问卷题目作为测试夹具嵌入到了生产源码库的 `GlassCore` 模块中！
同时在 [`:3584`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/NativeSessionStore.swift#L3584) 和 [`:3599`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/NativeSessionStore.swift#L3599) 编写了带有 `preconditionFailure` 的 `loadSnapshotTodoFixture` 和 `loadSnapshotGoalFixture`。

#### 2.10.2 根治方案
1. 立即将所有 snapshot fixture 方法从生产目标 [`NativeSessionStore.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/NativeSessionStore.swift) 剥离。
2. 将相关预览数据移至 `Tests` 或 Debug Preview Target 独立文件中，彻底净化生产业务模型。

---

### 2.11 内存无界膨胀：会话日志与事件缓存缺乏滑动窗口限制

#### 2.11.1 会话日志无界线性增长
在 [`glass/Sources/Core/Session/Runtime/SessionJournal.swift:140-146`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Runtime/SessionJournal.swift#L140-L146) 中：
```swift
let startRecordIndex = snapshot!.records.count
revision += 1
snapshot!.records.append(entry)
snapshot!.appliedThrough = last
snapshot!.revision = revision
snapshot!.mutation = .append(startRecordIndex: startRecordIndex)
rawEventsBySeq[event.seq] = event
return true
```
1. 随着长会话持续运行，`snapshot.records` 与 `rawEventsBySeq` 字典只增不减。
2. 在没有容量上限、没有基于时间戳或序列号的滑动窗口（Sliding Window）修剪机制的情况下，运行几天的桌面客户端将无节制地吞噬数百兆内存，最终被 macOS 系统因 OOM 强行杀进程。

#### 2.11.2 根治方案
1. 在 `SessionJournal` 中引入固定大小的内存滑动窗口或事件环形缓冲区（例如仅保留最近 2000 个活跃事件）。
2. 更早期的历史事件应下沉写入磁盘持久化或按需按页拉取，不再常驻常态内存字典。

---

## 3. 全量改动模块级审查详单

本节覆盖当前分支 275 个改动文件的模块级详细排查记录：

### 3.1 远端传输与 RPC/SSE 层 (`glass/Sources/Core/Remote/*`)
- **改动文件**：
  [`RemoteConnection.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteConnection.swift), 
  [`RemoteMuxConnection.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteMuxConnection.swift), 
  [`RemoteEventRuntime.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteEventRuntime.swift), 
  [`RemoteDTOModels.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteDTOModels.swift), 
  [`DomainAPIs.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/DomainAPIs.swift) 等。
- **审查发现**：
  1. `RemoteMuxConnection.swift` 存在高频堆分配与双重反序列化（详见 2.4）。
  2. `RemoteEventRuntime.swift` 存在目录清空与帧泄漏（详见 2.5）。
  3. `RemoteDTOModels.swift` 结构基本与官方 `rc.1` 对齐，但部分可选字段解析过于严苛。
  4. 删除了旧的 `SSEClient.swift` 与 `DSHAPIClient.swift`，但部分领域接口调用处仍然留有兼容垫片痕迹。

### 3.2 会话运行时与增量投影层 (`glass/Sources/Core/Session/*`)
- **改动文件**：
  [`SessionRuntime.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Runtime/SessionRuntime.swift), 
  [`SessionJournal.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Runtime/SessionJournal.swift), 
  [`NativeSessionStore.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/NativeSessionStore.swift), 
  [`ConversationNodeReducer.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationNodeReducer.swift), 
  [`ConversationCoreNodes.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift), 
  [`SessionProjectionStore.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/SessionProjectionStore.swift) 等。
- **审查发现**：
  1. `ConversationNodeReducer.swift` 的 $O(N^2)$ 重构回退性能炸弹（详见 2.1）。
  2. `NativeSessionStore.swift` 包含无关招聘面试题与崩溃断言（详见 2.10）。
  3. `SessionRuntime.swift` 消费期缺少指数退避重试（详见 2.8）。
  4. `SessionJournal.swift` 缺乏滑动窗口导致无界内存泄漏（详见 2.11）。
  5. 纯函数 Reducer 散落 15 处 `preconditionFailure`（详见 2.9）。

### 3.3 工作区与文件目录层 (`glass/Sources/Core/Workspace/*`, `glass/Sources/UI/Workspace/*`)
- **改动文件**：
  [`WorkspaceRuntime.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Workspace/WorkspaceRuntime.swift), 
  [`NativeWorkspaceStore.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Workspace/NativeWorkspaceStore.swift), 
  [`WorkspaceBrowserView.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Workspace/WorkspaceBrowserView.swift) 等。
- **审查发现**：
  1. `WorkspaceRuntime.swift` 在遭遇第二个 baseline 时直接清空本地状态并自毁连接（详见 2.8）。
  2. `NativeWorkspaceStore.swift` 和 `WorkspaceBrowserView.swift` 存在 5 处 `Dictionary(uniqueKeysWithValues:)`（详见 2.3）。
  3. 注释大量残留 `RC8` 过时描述。

### 3.4 宿主生命周期与进程调度 (`glass/Sources/Core/Host/*`)
- **改动文件**：
  [`HostDiagnostics.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Host/HostDiagnostics.swift), 
  [`HarnessHostProcess.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Host/HarnessHostProcess.swift) 等。
- **审查发现**：
  1. `HostDiagnostics.swift:141` 仍使用 `try! NSRegularExpression` 编译动态正则表达式，且缺少 O(1) 预过滤。
  2. 进程状态机在处理非预期退出时，缺乏优雅清理管道描述符的保障。

### 3.5 插件平原与 WebKit 桥接层 (`glass/Sources/PluginPlane/*`, `glass/Sources/Core/Plugin/*`)
- **改动文件**：
  [`GhostPlaneSlotRegistry.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneSlotRegistry.swift), 
  [`GhostPlaneSkeleton.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneSkeleton.swift), 
  [`GhostPlaneTapIndexReplay.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneTapIndexReplay.swift), 
  [`GhostPlaneModuleManifest.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneModuleManifest.swift) 等。
- **审查发现**：
  1. 插件元数据解析中充斥 5 处 `Dictionary(uniqueKeysWithValues:)` 崩溃隐患（详见 2.3）。
  2. 插件事件桥接存在多余的中间层转发分配。

### 3.6 原生交互视图与 Markdown 渲染 (`glass/Sources/UI/*`)
- **改动文件**：
  [`NativeMarkdownRenderer.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Conversation/NativeMarkdownRenderer.swift), 
  [`NativeConversationHeader.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Conversation/NativeConversationHeader.swift), 
  [`NativeToolViews.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Tooling/NativeToolViews.swift) 等。
- **审查发现**：
  1. `NativeConversationHeader.swift:48` 构造字典时调用崩溃构造器（详见 2.3）。
  2. `NativeMarkdownRenderer.swift` 在视图主线程高频使用 5 个跨行正则进行 HTML 与链接替换，卡顿明显。

### 3.7 官方规范清册与静态资产 (`glass/Sources/Spec/*`)
- **改动文件**：
  [`OfficialLocaleRuntimeCatalog.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Spec/OfficialLocaleRuntimeCatalog.swift), 
  [`OfficialUISpec.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Spec/OfficialUISpec.swift), 
  [`official-remote-contract-manifest.json`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Spec/Fixtures/official-remote-contract-manifest.json) 等。
- **审查发现**：
  1. 契约清册中部分类型描述为由不完整 AST 提取产生的截断字段。
  2. 多处静态资源加载失败直接触发 `preconditionFailure`。

### 3.8 自动化测试套件 (`glass/Tests/*`)
- **改动文件**：
  [`SessionProjectionIncrementalTests.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Tests/Core/SessionProjectionIncrementalTests.swift), 
  [`GhostPlaneModuleManifestTests.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Tests/Core/GhostPlaneModuleManifestTests.swift) 等数十个测试文件。
- **审查发现**：
  1. 官僚“做局”式测试：`SessionProjectionIncrementalTests.swift` 掩盖 $O(N^2)$ 性能灾难（详见 2.1）。
  2. 测试依然保留违反守则的 `replacingOccurrences`（详见 2.2）。
  3. 大量同义反复的虚假断言，未被门禁真正拦截。

### 3.9 CI 门禁、构建与代码生成脚本 (`glass/ci/*`, `tools/*`)
- **改动文件**：
  [`check-test-integrity.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/check-test-integrity.py), 
  [`check-official-interaction-scenes.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/check-official-interaction-scenes.py), 
  [`test-official-ghost-plane-contract.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/test-official-ghost-plane-contract.py), 
  [`generate_ghost_plane_contract.py`](file:///Users/newbiexvwu/deepseek-harness-glass/tools/spec-generation/generate_ghost_plane_contract.py) 等。
- **审查发现**：
  1. 门禁脚本无条件 `return 0`（详见 2.6）。
  2. 字符串对暗号校验（详见 2.6）。
  3. 子进程篡改套娃自测（详见 2.2）。
  4. 硬编码 Ubuntu 机器环境路径（详见 2.7）。

---

## 4. 整改修复实施路线与优先级矩阵

### 4.1 P0 级（阻断与崩溃缺陷，必须立即彻底修复）

1. **[拆除增量通道性能炸弹]**
   - **目标文件**：[`glass/Sources/Core/Session/Projection/Conversation/ConversationNodeReducer.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationNodeReducer.swift)
   - **行动**：
     - 重写 `affectsLocationFacts` 谓词，排除 `assistant/chunk` 等内容事件，仅保留严格的 `turn/start`、`turn/end` 等宏观边界事件。
     - 优化 [`ConversationCoreNodes.swift:555`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L555) 中的 `markVisible`，避免重复 trimming 产生的高频分配风暴。
     - 修复并真实验证 [`SessionProjectionIncrementalTests.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Tests/Core/SessionProjectionIncrementalTests.swift)，确保 10,000 个流式 chunk 追加可在 100ms 内平稳完成。

2. **[清除生产环境全部 14 处崩溃式字典构造]**
   - **目标文件**：
     - [`NativeSessionStore.swift:867`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/NativeSessionStore.swift#L867)
     - [`SessionProjectionStore.swift:47`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/SessionProjectionStore.swift#L47)
     - [`NativeWorkspaceStore.swift:65, 253`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Workspace/NativeWorkspaceStore.swift#L65)
     - [`WorkspaceBrowserView.swift:815, 854, 874`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Workspace/WorkspaceBrowserView.swift#L815)
     - [`NativeConversationHeader.swift:48`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Conversation/NativeConversationHeader.swift#L48)
     - [`GhostPlaneSlotRegistry.swift:70`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneSlotRegistry.swift#L70)
     - [`GhostPlaneModuleManifest.swift:52`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneModuleManifest.swift#L52)
     - [`GhostPlaneSkeleton.swift:112, 118`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneSkeleton.swift#L112)
     - [`GhostPlaneTapIndexReplay.swift:86`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Plugin/GhostPlaneTapIndexReplay.swift#L86)
     - [`NativeSchemaFormDraft.swift:35`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/UI/Settings/NativeSchemaFormDraft.swift#L35)
     - [`OfficialLocaleRuntimeCatalog.swift:47`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Spec/OfficialLocaleRuntimeCatalog.swift#L47)
   - **行动**：全面替换为 `uniquingKeysWith: { _, latest in latest }` 或 `mapValues`。

3. **[修复 RemoteEventRuntime 全局会话清空自杀漏洞]**
   - **目标文件**：[`glass/Sources/Core/Remote/RemoteEventRuntime.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteEventRuntime.swift)
   - **行动**：
     - 剥夺 `applySessionFrame` 局部错误向外传播并触发 `invalidateCatalog()` 的特权。
     - 对齐官方 [`manager.ts`](file:///Users/newbiexvwu/deepseek-harness/packages/api/session-controller/src/client/sessions/manager.ts)，将未命中缓存会话的处理改为可选链安全跳过。
     - 消除 `pendingSessionFrames` 无界累积造成的内存泄漏。

4. **[消除纯函数 Reducer 内所有 preconditionFailure]**
   - **目标文件**：
     - [`ConversationCoreNodes.swift:226-796`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationCoreNodes.swift#L226-L796)
     - [`ConversationWorkflowNodes.swift:95`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationWorkflowNodes.swift#L95)
     - [`ConversationDeliverablesNode.swift:61, 67`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationDeliverablesNode.swift#L61)
     - [`ConversationNode.swift:294`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Projection/Conversation/ConversationNode.swift#L294)
   - **行动**：对未知或不合法状态降级为无损跳过或默认空状态，绝不允许生产闪退。

5. **[实现长连接双态指数退避自愈]**
   - **目标文件**：
     - [`SessionRuntime.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Runtime/SessionRuntime.swift)
     - [`WorkspaceRuntime.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Workspace/WorkspaceRuntime.swift)
   - **行动**：在持续消费阶段捕获非取消错误后，增加 200ms $\rightarrow$ 3s 指数退避自愈重连，严禁直接消极 `return`。

---

### 4.2 P1 级（性能、协议韧性与可移植性缺陷）

1. **[优化 RemoteMuxConnection 双重反序列化与堆分配]**
   - **目标文件**：[`glass/Sources/Core/Remote/RemoteMuxConnection.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Remote/RemoteMuxConnection.swift)
   - **行动**：移除每帧构建 `Set<String>` 和键名死板白名单判断；将两阶段解码整合，直接单次反序列化目标载荷。
2. **[引入 SessionJournal 内存滑动窗口]**
   - **目标文件**：[`glass/Sources/Core/Session/Runtime/SessionJournal.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/Runtime/SessionJournal.swift)
   - **行动**：限制常驻内存事件上限，引入环形缓冲区或滚动截断，解决长时间运行 OOM 风险。
3. **[清除生成脚本硬编码 Ubuntu 机器路径]**
   - **目标文件**：[`tools/spec-generation/generate_ghost_plane_contract.py`](file:///Users/newbiexvwu/deepseek-harness-glass/tools/spec-generation/generate_ghost_plane_contract.py)
   - **行动**：移除 `/home/ubuntu/...` 路径，改用环境感知的标准命令探测。

---

### 4.3 P2 级（代码规范、门禁治理与虚假测试清除）

1. **[物理剥离生产 Target 内的招聘面试题与测试 Fixture]**
   - **目标文件**：[`glass/Sources/Core/Session/NativeSessionStore.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Sources/Core/Session/NativeSessionStore.swift)
   - **行动**：将 `loadSnapshotQuestionFixture`、`loadSnapshotTodoFixture`、`loadSnapshotGoalFixture` 彻底移出生产代码。
2. **[修复 GhostPlane 单测的 replacingOccurrences 反模式]**
   - **目标文件**：[`glass/Tests/Core/GhostPlaneModuleManifestTests.swift`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/Tests/Core/GhostPlaneModuleManifestTests.swift)
   - **行动**：使用独立的静态 JSON Fixture 替代正则/字符串篡改。
3. **[重构 CI 门禁：移除虚假套娃与无条件 return 0]**
   - **目标文件**：
     - [`glass/ci/check-test-integrity.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/check-test-integrity.py)
     - [`glass/ci/check-official-interaction-scenes.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/check-official-interaction-scenes.py)
     - [`glass/ci/test-official-ghost-plane-contract.py`](file:///Users/newbiexvwu/deepseek-harness-glass/glass/ci/test-official-ghost-plane-contract.py)
   - **行动**：删除套娃脚本，恢复真实的非零门禁阻断，废弃暗号字符串匹配。

---

### 4.4 验收标准与防回退机制
1. **编译零警告**：在 Swift 6 严格模式下，全量执行 `swift build` 必须实现零警告、零错误。
2. **真实压测绿灯**：执行 `SessionProjectionIncrementalTests.swift` 包含 10,000 个 `assistant/chunk` 的追加测试，要求在 **500 毫秒内** 完成，且内存不发生突增。
3. **网络混沌韧性验证**：在会话消费期间注入乱序状态事件（如提前到来的 `api-session/status`）、异常重连以及重复 baseline 帧，客户端必须平稳自愈，**绝对不允许全局目录清空或进程崩溃**。
4. **门禁真实性**：运行 `python3 glass/ci/check-test-integrity.py`，若存在同义反复断言必须退出码非零，彻底杜绝掩耳盗铃的形式主义测试。
