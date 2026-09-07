# DeepSeek Harness Glass 研发智能体与工程守则 (AGENTS.md)

> **适用对象**：所有参与本项目开发、重构、审查或编写测试的 AI 智能体（Agent）及人类开发者。  
> **核心原则**：以**真实运行态行为**与**系统韧性**为最高准则，坚决禁止形式主义、官僚自测、伪造对齐与合规套利。

---

## 目录
1. [项目工程基准与第一性原理](#1-项目工程基准与第一性原理)
2. [十四严禁反模式与具体错误代码剖析](#2-十四严禁反模式与具体错误代码剖析)
   - [反模式 1：形式主义自杀式崩溃断言与强制解包](#反模式-1形式主义自杀式崩溃断言与强制解包)
   - [反模式 2：脆弱的“文本对暗号”与正则伪测试](#反模式-2脆弱的文本对暗号与正则伪测试)
   - [反模式 3：流式热路径过度抽象与多重序列化损耗](#反模式-3流式热路径过度抽象与多重序列化损耗)
   - [反模式 4：凭空臆造官方协议、文案与本地化命名空间](#反模式-4凭空臆造官方协议文案与本地化命名空间)
   - [反模式 5：析构函数副作用跨界破坏共享运行环境](#反模式-5析构函数副作用跨界破坏共享运行环境)
   - [反模式 6：未阅 API 规范主观臆断平台桥接机制](#反模式-6未阅-api-规范主观臆断平台桥接机制)
   - [反模式 7：集成与烟雾测试强依赖外部环境导致 CI 脆弱](#反模式-7集成与烟雾测试强依赖外部环境导致-ci-脆弱)
   - [反模式 8：单测装载 AppKit 临时窗口未关闭系统动画导致 UAF / SIGSEGV 悬垂指针崩溃](#反模式-8单测装载-appkit-临时窗口未关闭系统动画导致-uaf--sigsegv-悬垂指针崩溃)
   - [反模式 9：传输层重构盲目“一刀切”误删官方核心 DTO 架构](#反模式-9传输层重构盲目一刀切误删官方核心-dto-架构)
   - [反模式 10：大文本数据流投影病态依赖跨行正则而不是 O(1) 边界切片](#反模式-10大文本数据流投影病态依赖跨行正则而不是-o1-边界切片)
   - [反模式 11：形式主义“自测套娃”与黑客式字符串抹除断言](#反模式-11形式主义自测套娃与黑客式字符串抹除断言)
   - [反模式 12：协议与契约提取病态依赖多行正则导致数据截断腐烂](#反模式-12协议与契约提取病态依赖多行正则导致数据截断腐烂)
   - [反模式 13：顺序同步帧脆弱断言导致全局桌面状态清空崩塌](#反模式-13顺序同步帧脆弱断言导致全局桌面状态清空崩塌)
   - [反模式 14：门禁硬编码魔数对暗号与官僚自测套娃](#反模式-14门禁硬编码魔数对暗号与官僚自测套娃)
3. [测试有效性第一性原理 (Anti-Theater Testing)](#3-测试有效性第一性原理-anti-theater-testing)
4. [Swift 并发与架构红线](#4-swift-并发与架构红线)
5. [提交前全量自检清单](#5-提交前全量自检清单)

---

## 1. 项目工程基准与第一性原理

1. **官方权威基准（Source of Truth）**：
   - 官方实现位于本地开发环境的 `~/deepseek-harness`。所有协议定义（Protocol DTO）、RPC/SSE 状态机行为、本地化词条（Locale Catalog）、主题 Token 及界面层次必须严格与官方上游对齐。
   - **严禁凭空想象**任何协议字段、错误码或本地化文案。
2. **韧性优先（Fault Tolerance & Resilience）**：
   - 客户端是长时间驻留的 macOS 原生桌面容器，必须能够在后端网络波动、异常帧、重复数据、并发竞态等恶劣场景下平稳自愈，**绝对不允许非致命错误直接让生产 App 崩溃（Crash）**。
3. **零编译警告与严格并发安全**：
   - 严格启用 Swift 6 并发检查模式，代码库必须保持 `swift build` 零警告、零错误。
4. **增量状态机纯函数隔离（Pure State Reducer）**：
   - 增量数据流状态机必须设计为零异常、零异步、零副作用的纯函数 `(State, Frame) -> State`。任何局部解析失败、乱序、未知 ID 均由 Reducer 内部进行无损容错对齐或单帧丢弃，**严禁向外层抛出错误，物理剥夺局部错误导致上层 Actor 触发 `invalidate()` 清空全局状态（`state = nil`）的自杀特权**。
5. **长连接网络流双态自愈机（Two-Phase Stream Resiliency）**：
   - 网络长连接消费 Task 必须严格区分“首帧协商期（Handshake Phase）”与“持续消费期（Runtime Phase）”：
     - **协商期**（首次建立连接，`continuation != nil`）：首帧握手或解码失败必须立即上抛给调用方，严禁假死挂起；
     - **消费期**（运行态持续消费，`continuation == nil`）：遭遇网络闪断、远端重置或帧解析异常时，**严禁直接消极 `return` 终结后台 Task 导致客户端沦为植物人**，必须在 Task 内部执行指数退避（200ms $\rightarrow$ 3s）自愈重连循环。

---

## 2. 十四严禁反模式与具体错误代码剖析

以下反模式均来自历史审查中发现的真实严重工程缺陷。任何 AI 智能体在提交代码时若重犯以下任意一种，均视为重大质量事故。

---

### 反模式 1：形式主义自杀式崩溃断言与强制解包

* **危害**：为了在代码中显式表达“数据必须唯一/必须严格递增”，强行使用 `try!`、`Dictionary(uniqueKeysWithValues:)` 或强制解包。当后端返回非幂等或轻微顺序重叠的数据时，直接引发 `SIGABRT`，让用户整个客户端闪退。
* **规则**：生产逻辑严禁使用崩溃式构造器。必须具备数据容错、优雅降级和日志报警能力。

#### 真实对比案例：[`glass/Sources/Core/Workspace/WorkspaceRuntime.swift`](glass/Sources/Core/Workspace/WorkspaceRuntime.swift)

```swift
// ❌ 错误做法：后端如果因为网络重试或状态同步返回重复 ID，生产直接 SIGABRT 崩溃！
let existingByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
```

```swift
// ✅ 正确做法：防御性冲突解决，保留最新状态，生产平稳容错
let existingByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
```

---

### 反模式 2：脆弱的“文本对暗号”与正则伪测试

* **危害**：使用 `replacingOccurrences` 或复杂正则去篡改带换行/缩进的多行格式化 JSON。由于字符换行、转义字符或 Raw String（`#""#`）未匹配，替换往往完全没有生效，测试变成了测空；或者一旦格式化工具重新排版，测试立即假红。
* **规则**：严禁通过字符串正则替换制造单测 Fixture。必须使用结构清晰、语义独立的专用 JSON Fixture 或强类型数据结构直接断言业务行为。

#### 真实对比案例：[`glass/Tests/Core/GhostPlaneModuleManifestTests.swift`](glass/Tests/Core/GhostPlaneModuleManifestTests.swift)

```swift
// ❌ 错误做法：用脆弱的 raw string 替换尝试篡改多行格式化 JSON，因缩进和换行符不匹配导致替换落空，测试名存实亡
let nonLinearJSON = officialJSON.replacingOccurrences(
    of: #",{"phase": "render", "requires": ["bootstrap"]}"#,
    with: #",{"phase": "render", "requires": ["missing"]}"#
)
XCTAssertThrowsError(try decoder.decode(GhostPlaneModuleManifest.self, from: Data(nonLinearJSON.utf8)))
```

```swift
// ✅ 正确做法：直接提供意图明确的独立 Fixture，精准检验循环依赖与阶段拓扑校验失败
let invalidPhaseJSON = """
{
  "schemaVersion": 1,
  "phases": [
    { "phase": "bootstrap", "requires": [] },
    { "phase": "render", "requires": ["non_existent_phase"] }
  ]
}
"""
let data = try XCTUnwrap(invalidPhaseJSON.data(using: .utf8))
XCTAssertThrowsError(try decoder.decode(GhostPlaneModuleManifest.self, from: data)) { error in
    guard case GhostPlaneManifestError.invalidPhaseDependency = error else {
        XCTFail("Unexpected error thrown: \(error)")
        return
    }
}
```

---

### 反模式 3：流式热路径过度抽象与多重序列化损耗

* **危害**：在 WebSocket/SSE 每秒几十帧高频流式传输的热路径上，为了所谓“通用数据结构”封装，先解码为泛型字典/枚举，重新 `JSONEncoder().encode` 变成二进制，再反序列化为业务结构体；或者在 SwiftUI 列表计算属性中，为无关行无脑反复触发反序列化。
* **规则**：热路径严禁二次编解码（Double Serialization）。只解包必要的外层元数据（如 `streamId`），直接用原始字节解码强类型载荷；视图计算属性必须快速守卫短路。

#### 真实对比案例：[`glass/Sources/Core/Remote/RemoteMuxConnection.swift`](glass/Sources/Core/Remote/RemoteMuxConnection.swift)

```swift
// ❌ 错误做法：每接收一帧，经历 Raw Bytes -> RemoteJSONValue -> Data -> Frame，造成 3 次内存分配与 CPU 浪费
let jsonValue = try JSONDecoder().decode(RemoteJSONValue.self, from: rawData)
let reencodedData = try JSONEncoder().encode(jsonValue)
let frame = try JSONDecoder().decode(Frame.self, from: reencodedData)
```

```swift
// ✅ 正确做法：只用超轻量信封提取分流 ID，原始二进制 Data 直接单次解码目标 Frame
private struct MuxStreamEnvelope: Decodable {
    let streamId: String?
}
let envelope = try JSONDecoder().decode(MuxStreamEnvelope.self, from: rawData)
let frame = try JSONDecoder().decode(Frame.self, from: rawData)
```

#### 真实对比案例：[`glass/Sources/UI/Tooling/NativeToolViews.swift`](glass/Sources/UI/Tooling/NativeToolViews.swift)

```swift
// ❌ 错误做法：每一行工具项渲染，不论是 read_file 还是 grep，都无脑尝试做终端参数 JSON 反序列化
var terminalPayload: TerminalPayload? {
    guard let input = item.input else { return nil }
    return try? JSONDecoder().decode(TerminalPayload.self, from: Data(input.utf8))
}
```

```swift
// ✅ 正确做法：名称守卫提前短路，非终端类工具零序列化开销
var terminalPayload: TerminalPayload? {
    guard item.name == "bash" || item.name == "terminal", let input = item.input else { return nil }
    return try? JSONDecoder().decode(TerminalPayload.self, from: Data(input.utf8))
}
```

---

### 反模式 4：凭空臆造官方协议、文案与本地化命名空间

* **危害**：脱离上游源码臆造文案或猜测命名空间。例如误以为工具详情国际化文本在 `ui-conversation`，甚至脑补输入框占位符为 `"Message the agent"`。导致线上渲染时取不到任何文本退化为空白，测试也只能与虚假数据互保。
* **规则**：凡涉及协议字段、枚举值或本地化文案，必须查阅 `~/deepseek-harness` 源码确认。界面取值必须提供完备的多命名空间回退。

#### 真实对比案例：[`glass/Sources/Spec/OfficialUISpec.swift`](glass/Sources/Spec/OfficialUISpec.swift) 与 [`glass/Sources/UI/Tooling/NativeToolViews.swift`](glass/Sources/UI/Tooling/NativeToolViews.swift)

```swift
// ❌ 错误做法：主观臆造不存在的文案与错误的命名空间（官方定义在 ui-chat）
public static let composerDefaultPlaceholder = "Message the agent"
let inputLabel = catalog.string(for: "details.input", in: "ui-conversation") // 运行期恒为 nil！
```

```swift
// ✅ 正确做法：核对官方 LocaleCatalog，对齐官方真实占位符，并建立层级回退机制
public static let composerDefaultPlaceholder = "Message or run a task... / commands, @ files or sessions"
let inputLabel = catalog.string(for: "details.input", in: "ui-chat")
    ?? catalog.string(for: "details.input", in: "ui-conversation")
    ?? "Input"
```

---

### 反模式 5：析构函数副作用跨界破坏共享运行环境

* **危害**：在具体业务实例的 `deinit` 中过度追求“无死角清理”，直接调用 `FileManager.removeItem(at: rootDirectory)` 将传入的全局或共享公共临时目录整个抹去。导致后续实例或其他并发操作全部抛出 `CocoaError 4 (File not found)`。
* **规则**：共享根目录所有权属于系统或外部调用方。单个组件实例只能创建属于自己的 `UUID()` 隔离子目录，且析构时只允许清理该独立子目录。

#### 真实对比案例：[`glass/Sources/PluginPlane/GhostPlaneTemporaryFileStore.swift`](glass/Sources/PluginPlane/GhostPlaneTemporaryFileStore.swift)

```swift
// ❌ 错误做法：实例释放时，竟然物理删除传入的共享公共根目录！
public init(rootDirectory: URL) {
    self.root = rootDirectory
}
deinit {
    try? FileManager.default.removeItem(at: self.root) // 毁灭性副作用！
}
```

```swift
// ✅ 正确做法：实例隔离生命周期，只清理专属子目录，绝不越界侵害宿主共享环境
public init(rootDirectory: URL) {
    self.instanceDirectory = rootDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: self.instanceDirectory, withIntermediateDirectories: true)
}
deinit {
    try? FileManager.default.removeItem(at: self.instanceDirectory)
}
```

---

### 反模式 6：未阅 API 规范主观臆断平台桥接机制

* **危害**：凭想象使用底层系统 API。例如使用 WebKit 的 `callAsyncJavaScript` 时，误以为 Swift 传参字典会变成 JS 的 `arguments.xxx` 对象，导致注入 JS 永远取到 `undefined`。
* **规则**：使用系统 API 必须尊重平台规范：WebKit `callAsyncJavaScript(..., arguments: ["key": value])` 会将字典的 key 作为**具名形参**直接注入到 JS 作用域，必须在脚本中直接访问该形参变量。

#### 真实对比案例：[`glass/Sources/PluginPlane/GhostPlaneWebViewHost.swift`](glass/Sources/PluginPlane/GhostPlaneWebViewHost.swift)

```swift
// ❌ 错误做法：在 JS 中访问 arguments.records，运行时恒为 undefined
let js = """
return window.__dsh_plane.dispatch({
    records: arguments.records,
    pluginIDs: arguments.pluginIDs
});
"""
webView.callAsyncJavaScript(js, arguments: ["records": records, "pluginIDs": ids], in: nil, in: .page)
```

```swift
// ✅ 正确做法：直接使用字典 key 对应的形参名
let js = """
return window.__dsh_plane.dispatch({
    records: records,
    pluginIDs: pluginIDs
});
"""
webView.callAsyncJavaScript(js, arguments: ["records": records, "pluginIDs": ids], in: nil, in: .page)
```

---

### 反模式 7：集成与烟雾测试强依赖外部环境导致 CI 脆弱

* **危害**：在集成或冒烟测试（Smoke Test）中，强行假设外部守护进程（如 Node/Go 宿主）在当前机器上一定启动，直接对环境变量进行强制解包 `!`。导致在纯本地环境、单测容器或离线构建时直接崩溃。
* **规则**：所有依赖外部网络服务、宿主后台进程或外部环境变量的测试，必须使用 `XCTSkip` 优雅跳过，不得阻断基础单元测试管道。

#### 真实对比案例：[`glass/Tests/Core/HarnessHostTransportSmokeTests.swift`](glass/Tests/Core/HarnessHostTransportSmokeTests.swift)

```swift
// ❌ 错误做法：未配环境变量直接 force unwrap 崩溃，测试全套阵亡
let hostNode = ProcessInfo.processInfo.environment["DSH_GLASS_HOST_NODE"]!
```

```swift
// ✅ 正确做法：缺少必要环境时使用 XCTSkip，保证单测基础流水线全绿
guard let hostNode = ProcessInfo.processInfo.environment["DSH_GLASS_HOST_NODE"], !hostNode.isEmpty else {
    throw XCTSkip("Skipping host smoke test: DSH_GLASS_HOST_NODE environment variable not configured.")
}
```

---

### 反模式 8：单测装载 AppKit 临时窗口未关闭系统动画导致 UAF / SIGSEGV 悬垂指针崩溃

* **危害**：在单测或视图测试中，为了布局或无障碍元素检查，创建临时 `NSWindow` 并调用 `window.makeKeyAndOrderFront(nil)`，但未禁用动画（未设置 `window.animationBehavior = .none`）且未设置 `window.isReleasedWhenClosed = false`。AppKit 会默认启动异步的 `_NSWindowTransformAnimation`；单测结束窗口关闭后，CoreAnimation 观察者回调触发，动画对象析构解引用已销毁的野指针，在 `_NSWindowTransformAnimation dealloc` 中引发致命的 `EXC_BAD_ACCESS (SIGSEGV 11)` 间歇性崩溃。
* **规则**：所有涉及 `NSWindow` 或 AppKit 视图容器的单测，**必须且只能通过统一的 `IsolatedTestWindowHarness` 执行**，严禁在测试方法中自行裸写 `NSWindow(...)`。

#### 真实对比案例：[`glass/Tests/App/IsolatedTestWindow.swift`](glass/Tests/App/IsolatedTestWindow.swift) 与 [`glass/Tests/App/NativeMaterialIsolationRuntimeTests.swift`](glass/Tests/App/NativeMaterialIsolationRuntimeTests.swift)

```swift
// ❌ 错误做法：测试中裸写 NSWindow 且未禁用动画，单测结束 CoreAnimation 动画对象野指针崩溃！
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = host
window.makeKeyAndOrderFront(nil)
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
defer { window.close() } // 抛出 EXC_BAD_ACCESS: -[_NSWindowTransformAnimation dealloc]
```

```swift
// ✅ 正确做法：统一收拢至 IsolatedTestWindowHarness，强行关闭动画与自动释放，确定性 defer 回收
IsolatedTestWindowHarness.withHostedView(view) { host in
    XCTAssertTrue(
        visualEffects(in: host).isEmpty,
        "D3 violation: mounted an ad-hoc NSVisualEffectView in its runtime content tree."
    )
}
```

---

### 反模式 9：传输层重构盲目“一刀切”误删官方核心 DTO 架构

* **危害**：在退役旧网络传输层（如废弃旧 HTTP Client）时，不加仔细甄别，将挂载在同一文件底部的几十个官方协议模型（如 `SessionEventDTO`、`SessionSubscribedDTO`、`SessionJobDTO`、`SettingsNamespaceDTO` 等）直接全量物理删除，导致会话、投射、设置等全模块编译大面积瘫痪。
* **规则**：传输机制（Transport mechanism）与官方数据传输契约（DTO Contract）必须严格分层。重构网络客户端前，必须先将协议 DTO 妥善收拢至强类型的独立模型文件（如 [`glass/Sources/Core/Remote/RemoteDTOModels.swift`](glass/Sources/Core/Remote/RemoteDTOModels.swift)）。

#### 真实对比案例：[`glass/Sources/Core/Remote/RemoteDTOModels.swift`](glass/Sources/Core/Remote/RemoteDTOModels.swift)

```swift
// ❌ 错误做法：退役 DSHAPIClient 时一刀切物理删除文件，60+ 核心 DTO 直接蒸发，项目无法构建！
// git rm glass/Sources/Core/Transport/DSHAPIClient.swift (连带抹杀 SessionEventDTO、SessionSubscribedDTO...)
```

```swift
// ✅ 正确做法：将传输层逻辑与官方 DTO 规范彻底解耦，收拢为专属纯数据契约层
// glass/Sources/Core/Remote/RemoteDTOModels.swift:
struct SessionEventDTO: Decodable, Sendable, Identifiable {
    let type: String
    let seq: Int
    let time: Double
    let data: JSONValue
    let surfaceOp: JSONValue?
    let sourceEventSeqs: [Int]?
    let ignorable: Bool?
    ...
}
```

---

### 反模式 10：大文本数据流投影病态依赖跨行正则而不是 O(1) 边界切片

* **危害**：在工具调用结果卡片投射（如终端输出或大文件读取）中，处理可能包含数十万行或几兆字节的原始文本时，无脑使用 `try! NSRegularExpression` 或 `[\s\S]*` 跨行匹配。对于 10MB 的工具输出，不仅触发昂贵的 `NSString` 全量内存桥接复制，还会引发灾难性的正则回溯死锁和内存飙升。
* **规则**：大文本热路径必须使用 O(1) 前缀/后缀短路、字符切片或尾部反向查找，彻底杜绝回溯型正则表达式。

#### 真实对比案例：[`glass/Sources/Core/Session/Projection/Tooling/NativeRawToolCardProjector.swift`](glass/Sources/Core/Session/Projection/Tooling/NativeRawToolCardProjector.swift)

```swift
// ❌ 错误做法：在 10MB 文本上触发 NSString 拷贝与跨行通配，卡死主线程
private static let readEnvelope = try! NSRegularExpression(
    pattern: #"^<path>[^\n]*</path>\n<type>file</type>\n<content>\n[\s\S]*\n</content>$"#
)
```

```swift
// ✅ 正确做法：O(1) 快速守卫与区间切片，零内存桥接，毫秒级响应
private static func matchesReadEnvelope(_ text: String) -> Bool {
    guard text.hasPrefix("<path>"),
          text.hasSuffix("\n</content>"),
          let separatorRange = text.range(of: "</path>\n<type>file</type>\n<content>\n")
    else { return false }
    let pathContent = text[text.index(text.startIndex, offsetBy: 6)..<separatorRange.lowerBound]
    return !pathContent.contains("\n")
}
```

---

### 反模式 11：形式主义“自测套娃”与黑客式字符串抹除断言

* **危害**：为了完成门禁覆盖率指标，编写专门篡改 JSON 运行另一个 Python 脚本并硬编码断言检查特定报错字符串（如 `"38 reviewed codes"`、`"token"`）的套娃脚本；或者在合规检查中，使用 `raw.lower().replace('persistedlaunchtoken', '')` 后暴力搜索子串 `'token'`。一旦业务新增 `shadowedTokenCount` 属性，测试直接假报警。
* **规则**：严禁自测套娃。隐私与契约检查必须通过结构化 JSON 解析与 AST 遍历执行，禁止对整文件源码使用文本子串抹除技巧。

#### 真实对比案例：[`glass/ci/check-authenticated-host-fixtures.py`](glass/ci/check-authenticated-host-fixtures.py)

```python
# ❌ 错误做法：黑客式字符串抹除后全局搜索子串，极度脆弱且极易误报正常字段
require('token' not in raw.lower().replace('persistedlaunchtoken', ''), 'fixture contains unexpected token text')
```

```python
# ✅ 正确做法：结构化解析 JSON，针对敏感字典与认证键值进行确定性模式校验
parsed = json.loads(raw)
for pattern in FORBIDDEN_CREDENTIAL_PATTERNS:
    require(pattern.search(raw) is None, f'fixture leaked sensitive credential pattern')
```

---

### 反模式 12：协议与契约提取病态依赖多行正则导致数据截断腐烂

* **危害**：使用脆弱的正则表达式提取 TypeScript 复杂接口（如 `RemoteErrorDetailsMap`）。当类型声明跨行时，正则仅捕获首行，把类型描述符截断为残废的单字符 `'{'` 或半截属性声明，并写入协议清册 `official-remote-contract-manifest.json`，导致契约元数据严重腐烂。
* **规则**：凡提取官方协议与类型定义，必须使用 TypeScript Compiler API 进行 AST 解析，坚决禁止使用脆弱的正则表达式猜测 AST 语法树。

#### 真实对比案例：[`tools/spec-generation/generate_official_remote_contract_manifest.py`](tools/spec-generation/generate_official_remote_contract_manifest.py) 与 [`tools/spec-generation/extract_official_remote_contract_ast.mjs`](tools/spec-generation/extract_official_remote_contract_ast.mjs)

```python
# ❌ 错误做法：用单行正则匹配多行类型，detailsType 被腰斩为 "{"，协议清册数据完全腐烂！
property_pattern = re.compile(r"['\"]([^'\"]+/[^'\"]+)['\"]\s*:\s*([^\n;]+(?:\{[^}]*\})?)")
# 输出结果：
# "code": "session/conflict",
# "detailsType": "{"
```

```javascript
// ✅ 正确做法：使用 TypeScript 编译器 AST 遍历节点，提取完整强类型描述
if (ts.isInterfaceDeclaration(node) && node.name.text === 'RemoteErrorDetailsMap') {
  for (const member of node.members) {
    if (ts.isPropertySignature(member) && member.name) {
      const code = member.name.getText(sourceFile).replace(/^['"]|['"]$/g, '')
      const detailsType = member.type ? member.type.getText(sourceFile).replace(/\s+/g, ' ').trim() : 'unknown'
      declaredErrors.set(code, { detailsType, sourcePath: relPath })
    }
  }
}
// 输出结果：
// "code": "session/conflict",
// "detailsType": "{ readonly sessionId: SessionId readonly requestedCwd: string readonly existingCwd?: string }"
```

---

### 反模式 13：顺序同步帧脆弱断言导致全局桌面状态清空崩塌

* **危害**：在长连接增量事件处理（如 `.order(workspaceIDs)`）中，强行断言服务端下发的排序 ID 列表与本地内存列表数量完全一致、集合完全等价（`guard workspaceIDs.count == current.items.count, Set(workspaceIDs) == Set(byID.keys) else { throw invalidOrder }`）。由于网络延迟或本地新建/删除操作的微小时序差，一旦产生微小偏离，直接抛出异常导致 `invalidate`，将客户端全局状态直接置为 `nil`，用户侧边栏列表瞬间全部消失！
* **规则**：增量数据流处理必须具备防御性容错能力。对已知 ID 依据排序指令重排，对未知 ID 忽略，对本地遗留 ID 保留追加到末尾，严禁因顺序帧轻微漂移而自杀式清空整个运行时。

#### 真实对比案例：[`glass/Sources/Core/Workspace/WorkspaceRuntime.swift`](glass/Sources/Core/Workspace/WorkspaceRuntime.swift)

```swift
// ❌ 错误做法：严苛断言集合完全相等，网络并发稍有不一致直接抛错触发 invalidate 清空所有工作区！
case let .order(workspaceIDs):
    let byID = Dictionary(current.items.map { ($0.workspaceId, $0) }, uniquingKeysWith: { _, new in new })
    guard workspaceIDs.count == current.items.count,
          Set(workspaceIDs) == Set(byID.keys)
    else { throw WorkspaceRuntimeError.invalidOrder } // 抛错导致整个 state = nil！
    current.items = workspaceIDs.compactMap { byID[$0] }
```

```swift
// ✅ 正确做法：防御性排序对齐，排已知项、略未知项、留本地项，生产坚如磐石
case let .order(workspaceIDs):
    let byID = Dictionary(current.items.map { ($0.workspaceId, $0) }, uniquingKeysWith: { _, new in new })
    var ordered: [RemoteWorkspaceView] = []
    var seenIDs = Set<String>()
    for id in workspaceIDs {
        if let item = byID[id], !seenIDs.contains(id) {
            ordered.append(item)
            seenIDs.insert(id)
        }
    }
    for item in current.items where !seenIDs.contains(item.workspaceId) {
        ordered.append(item)
    }
    current.items = ordered
```

---

### 反模式 14：门禁硬编码魔数对暗号与官僚自测套娃

* **危害**：在 CI 协议门禁中硬编码接口数量或错误码常量（如 `len(closedRemoteErrors) == 38`、`len(procedures) == 51`），并编写起子进程专门篡改 JSON 捕获报错字符串的“自测套娃脚本”（如 `test-official-remote-contract.py`）。当官方上游增加错误码或接口时，门禁因魔数不符假报警；而在类型定义被截断甚至残损时，却因数量凑齐而完全失明放行！自测套娃脚本不仅白白消耗 CI 资源，更给开发者制造了虚假的“门禁高覆盖率”幻觉。
* **规则**：
  1. 门禁严禁硬编码任何魔数常量。契约校验必须基于**官方 AST 导出的确定性全量符号集合闭包比对**或**候选产物与基线的确定性 Diff**；
  2. 提取的任何类型定义字符串必须通过**栈式括号平衡（`{}`、`[]`、`()`、`<>`）校验**，严禁单字符残废类型（如 `{`）入库；
  3. 坚决禁止编写子进程篡改自测套娃脚本。

#### 真实对比案例：[`glass/ci/check-official-remote-contract.py`](glass/ci/check-official-remote-contract.py)

```python
# ❌ 错误做法：写死常量魔数对暗号；上游更新直接报假警，类型被截断却视而不见！
if len(procedures) != 51:
    fail("procedures must contain exactly the 51 reviewed rc.1 endpoints")
if len(errors) != 38:
    fail("closedRemoteErrors must contain exactly the 38 reviewed codes")
```

```python
# ✅ 正确做法：去魔数化，基于动态非空校验、唯一性集合与栈式括号平衡完整性门禁
if not isinstance(procedures, list) or not procedures:
    fail("procedures must be a non-empty list of reviewed endpoints")
for procedure in procedures:
    validate_type_syntax(procedure["returnType"], f"{procedure['endpoint']} returnType")

for entry in errors:
    validate_type_syntax(entry["detailsType"], f"error '{entry['code']}' detailsType")
```

---

## 3. 测试有效性第一性原理 (Anti-Theater Testing)

所有测试代码必须服务于**真实生产场景的韧性与正确性**，严禁合规演戏：

1. **测行为，不测文本（Test Behavior, Not Text）**：
   - 严禁通过读取项目自身 `.swift` 源代码进行正则扫描、统计行数、或断言函数出现次数来充当“单测”。
2. **具备可证伪性与重构容忍度（Falsifiability & Refactor-Tolerance）**：
   - 当业务逻辑被破坏时，测试必须红灯报错；
   - 当仅仅重构内部结构、提取私有函数或排版调整而功能保持不变时，测试必须稳定全绿。
3. **混沌与故障注入覆盖（Chaos & Fault Injection）**：
   - 重点覆盖非 Happy Path：网络闪断自愈、流式重连退避、乱序帧重排、恶性格式报文丢弃与隔离。
4. **混沌工程与状态不变量防线（Chaos Engineering & Invariant Proofs）**：
   - 对于核心领域状态机（如 `WorkspaceStateReducer`、`SessionJournal`），必须编写基于伪随机数发生器（PRNG）的确定性混沌风暴注入单测（如 1,000 次连续乱序、脏数据、未知 ID、迟到 Baseline 冲击）；
   - 必须在每次迭代后断言数学级核心不变量（如：元素 ID 严格全局唯一、集合无损守恒、无异常无崩溃），并施加严格的时间性能预算（< 50ms），确保高频极端场景下坚不可摧。

---

## 4. Swift 并发与架构红线

1. **严格遵循 Actor 边界**：
   - 严禁将非 Sendable 的流式迭代器（如 `AsyncThrowingStream.Iterator`）跨 Task 或跨 Actor 逃逸传递。流的消费与首帧协商必须在同个 Actor 上下文内完成。
2. **无闭包 Sendable 隐式捕获**：
   - 在异步测试辅助函数中，使用 Actor 隔离或等待机制（如 `waitForLoad`），禁止在普通闭包中可变捕获跨线程共享状态。
3. **严格模块分层**：
   - `Core` 负责核心数据模型与通信，严禁引入 AppKit/SwiftUI 视图或直接控制 WebView；
   - `UI` 只依赖 `Core`，禁止绕过 Facade 越权调用私有通信管道；
   - `PluginPlane` 负责隔离沙箱，严禁红区凭证与内部数据向插件平面的 loopback 逃逸。

---

## 5. 提交前全量自检清单

在提交任何代码或宣布任务完成之前，必须依次在终端执行并确认以下检查全部通过：

```bash
# 1. 确保构建零警告、零错误（启用严格 Swift 6 并发安全）
swift build --package-path glass

# 2. 运行全部单元测试与混沌不变量测试（确保 460+ 测试 0 失败、0 崩溃）
swift test --package-path glass

# 3. 运行官方契约去魔数与类型括号平衡门禁
python3 glass/ci/check-official-remote-contract.py --official-root .reference/deepseek-harness

# 4. 运行认证宿主 Fixture 门禁
python3 glass/ci/check-authenticated-host-fixtures.py

# 5. 运行测试完整性门禁（反自测套娃与虚假断言）
python3 glass/ci/check-test-integrity.py

# 6. 运行 CI 工作流拓扑门禁
python3 glass/ci/test-ci-workflow-layout.py

# 7. 运行 Markdown 链接有效性校验
python3 tools/check-markdown-links.py
```
