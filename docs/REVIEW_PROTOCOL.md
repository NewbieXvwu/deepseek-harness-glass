# 原生迁移审查协议

本协议落实 `D0–D5`。每个变更有唯一可写实现作者；其余审查角色只能提交只读证据、评论或阻塞结论。实现作者不得自行批准自己的来源映射、视觉对照或 Glass 使用。

| 审查角色 | 必须检查的证据 | 阻塞条件 |
|---|---|---|
| 官方规格 | `official-ui-catalog.json`、上游组件/locale/token/图标来源、场景目录。 | 可见文本、图标、顺序、尺寸、状态没有锁定官方来源。 |
| Host 协议 | DTO diff、RPC/SSE fixture、错误/取消/重连测试。 | Feature 绕过 facade，或以伪本地状态取代 Host authority。 |
| 原生架构 | 模块依赖、并发边界、生命周期测试、D0 扫描。 | `Core`/`UI` 引入 WebView、进程控制或未分层的 URL/字典解析。 |
| 视觉与无障碍 | 同条件官方/原生截图、layout rectangles、键盘、VoiceOver、对比度/透明度。 | 任何未分类偏差，或仅凭肉眼声明“接近”。 |
| Liquid Glass | `GlassPolicy`、运行态证据、Reduce Transparency 行为。 | Glass 覆盖官方正文、Hero、composer、代码或消息表面，或没有 policy。 |
| 插件与安全 | Ghost Plane 分流路由、绿区 target 登记、红/绿区隔离、loopback same-origin 策略、事件桥无障碍语义。 | 红区（官方内容渲染）侵入 WebView，或插件平面逃逸 loopback 限制。 |
| 发布门禁 | 全部 CI 工件、支持矩阵、版本变更、签名/公证状态。 | D0–D5 任一失败、证据缺失或 Host build 未验证。 |

## 每个模块 PR 的必需证据包

1. 任务编号、官方 commit、Host build 和 UI spec revision。
2. 组件—来源映射，包含 locale key、token、图标和官方场景。
3. 行为测试：RPC/SSE fixture、reducer snapshot，以及失败/取消/重连路径。
4. 同窗口、主题、辅助功能条件下的官方与原生截图、布局矩形和偏差分类。
5. VoiceOver、键盘与 Reduce Transparency/Contrast/Motion 证据。
6. 若使用 `glassEffect`，附 `GlassPolicy`、运行态窗口截图与不侵入正文的说明。
7. D0/D1 静态门禁、编译和相关回归结果。
8. 与实现作者不同的规格审查和视觉/功能审查结论；任一为阻塞时不得合并。

## 偏差处置

偏差只能分类为 `source-missing`、`text`、`asset`、`geometry`、`state`、`system-glass` 或 `font-rendering`。
前五类须修复；后两类只有在来源、几何、平台设置与辅助功能证据完整时才能被批准。禁止通过新增产品文案、系统图标或未经来源支持的装饰来掩盖偏差。


## 测试工程第一性原理与反形式主义铁律 (Anti-Theater Quality Principles)

为防止自动化 Agent 进行合规套利、编造无效测试，所有测试编写必须遵守以下四大第一性原理：

1. **验证「运行态行为」，严禁「源码文本对暗号」 (Test Behavior, Not Text)**
   * 测试必须在运行期（Runtime）通过执行代码、调度状态机、模拟网络或渲染真实视图来验证系统输出；
   * **严厉禁止**：编写任何将项目自身 `.swift` 源代码作为纯文本进行关键字查找、正则匹配（`in text`）、统计特定行数或代码出现次数（`count == N`）的虚假测试脚本。

2. **具备「可证伪性」与「重构容忍度」 (Falsifiability & Refactor-Tolerance)**
   * **合格测试的标准**：业务逻辑出错时必然失败红灯；重构实现、提取子函数但功能正常时**必然保持全绿**；
   * 任何因重命名局部变量或代码排版调整就导致假报警的脆弱测试（Brittle Tests），一律定性为无效测试并打回重构。

3. **全生命周期边界与系统韧性覆盖 (Resilience & Lifecycle Testing)**
   * 严禁只测 Happy Path；必须重点覆盖：
     * **网络异常与混沌**：SSE 断线重连、WebSocket 帧乱序、并发取消、Host 重启自愈；
     * **极端压力与大载荷**：千条长消息会话、超大 Markdown 渲染、内存泄漏与释放；
     * **插件平面隔离**：Ghost Plane 多次装卸后的内存清理、导航拦截与红/绿区边界复核。

4. **工具自由，各司其职 (Right Tool for the Job)**
   * 鼓励根据场景自由选用最适合的高效工具：纯逻辑/状态机用原生 `XCTest`，并发/异步网络用 Swift `async/await` 自动化测试，多进程/Host 集成用自动化 Shell 冒烟，性能压力用 Benchmark 测试套件。
