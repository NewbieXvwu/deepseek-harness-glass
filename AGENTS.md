# DeepSeek Harness Glass 研发智能体与工程守则 (AGENTS.md)

> **适用对象**：所有参与本项目开发、重构、审查或编写测试的 AI 智能体（Agent）及人类开发者。  
> **核心原则**：以**真实运行态行为**与**系统韧性**为最高准则，坚决禁止形式主义、官僚自测、伪造对齐与合规套利。

---

## 目录
1. [项目工程基准与第一性原理](#1-项目工程基准与第一性原理)
2. [七大严禁反模式与具体错误代码剖析](#2-七大严禁反模式与具体错误代码剖析)
   - [反模式 1：形式主义自杀式崩溃断言与强制解包](#反模式-1形式主义自杀式崩溃断言与强制解包)
   - [反模式 2：脆弱的“文本对暗号”与正则伪测试](#反模式-2脆弱的文本对暗号与正则伪测试)
   - [反模式 3：流式热路径过度抽象与多重序列化损耗](#反模式-3流式热路径过度抽象与多重序列化损耗)
   - [反模式 4：凭空臆造官方协议、文案与本地化命名空间](#反模式-4凭空臆造官方协议文案与本地化命名空间)
   - [反模式 5：析构函数副作用跨界破坏共享运行环境](#反模式-5析构函数副作用跨界破坏共享运行环境)
   - [反模式 6：未阅 API 规范主观臆断平台桥接机制](#反模式-6未阅-api-规范主观臆断平台桥接机制)
   - [反模式 7：集成与烟雾测试强依赖外部环境导致 CI 脆弱](#反模式-7集成与烟雾测试强依赖外部环境导致-ci-脆弱)
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

---

## 2. 七大严禁反模式与具体错误代码剖析

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

## 3. 测试有效性第一性原理 (Anti-Theater Testing)

所有测试代码必须服务于**真实生产场景的韧性与正确性**，严禁合规演戏：

1. **测行为，不测文本（Test Behavior, Not Text）**：
   - 严禁通过读取项目自身 `.swift` 源代码进行正则扫描、统计行数、或断言函数出现次数来充当“单测”。
2. **具备可证伪性与重构容忍度（Falsifiability & Refactor-Tolerance）**：
   - 当业务逻辑被破坏时，测试必须红灯报错；
   - 当仅仅重构内部结构、提取私有函数或排版调整而功能保持不变时，测试必须稳定全绿。
3. **混沌与故障注入覆盖（Chaos & Fault Injection）**：
   - 重点覆盖非 Happy Path：网络闪断自愈、流式重连退避、乱序帧重排、恶性格式报文丢弃与隔离。

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
# 1. 确保构建零警告、零错误
swift build

# 2. 运行全部单元测试（确保 0 失败、0 错误、外部测试优雅跳过）
swift test

# 3. 运行宿主升级治理报告核验
python3 tools/check-host-upgrade-report.py

# 4. 运行 Markdown 链接有效性校验
python3 tools/check-markdown-links.py
```
