# 专项提案：第三方插件全兼容运行时（Ghost Plane 幽灵平面）

| | |
|---|---|
| 状态 | 草案（待评审） |
| 取代 | 原「渐进双轨制 + `PluginWebHost` 单卡片沙箱」设计（TODO T11 系列 v1） |
| 官方基准 | `deepseek-ai/deepseek-harness` `0.1.1-rc.1`（commit `528c682e`）；契约红线仍以 `SupportedHostBuilds.json` 锁定 build 为 verified 判据 |
| 证据基础 | 18 个高热度社区插件（`dsh-plugin` topic 头部，覆盖 toolkit / ui-panel / theme / tui / hybrid 全形态）的源码实读分析，全部结论带文件:行号级证据；官方槽位全集经三路独立分析交叉验证 |

---

## 1. 背景与动机

对 18 个真实生态插件的实证分析表明：按原双轨制设计直接安装，兼容度两极分化——纯 Host 工具类 95~100%，而任何依赖 client 半区 UI 承载的插件大面积静默失效（0~45%）。失效不是工程量问题，而是原「单卡片沙箱」模型的结构性缺陷：它假设插件 UI 可以被拆成孤立卡片，但生态的现实是插件深度耦合官方页面的**槽位位置、服务注入与文档级 DOM 契约**。

### 1.1 四类失效根因

1. **装载语义全有或全无**。client entry 的 `inject` 声明任一服务缺失 ⇒ 整个 fiber 停在 pending、不激活（`packages/client/web/src/boot.ts:148-156`）。原生壳内不存在 `inputTriggers`、`betterSidebar` 等服务时，插件整体静默消失而非降级。
2. **槽位承载面结构性缺失**。官方槽位是 Web 页面内的 React 插槽注册表（`ui-slots` SlotCore / `runtime/src/client/slots.ts:93` SlotRegistry）。`conversation.input.dock/overlay/right`、`sidebar.*`、`tool.call.toolview`、`conversation.chat.turnTail` 全部依赖官方 Web 的组件树位置，原生壳无渲染点。
3. **文档级 DOM 侵入在隔离环境空转**。`querySelectorAll('[role="menu"]')`、body 级 `MutationObserver`、`document.body.appendChild` 浮层、`window.getSelection()` 划词——iframe 沙箱与宿主 DOM 互相隔离，此类能力全部静默失效。
4. **全局契约与平台事实**。`window.__ModuleLoader__` 是官方现行装载契约；部分插件依赖 `webServer.tapIndex` 注入主页面的全局令牌（如 `__DSH_MP_TOKEN__`），单卡片容器内天然不存在。

### 1.2 关键洞察

没有任何插件想要"官方的像素"，它们想要的是**官方的坐标和事件**：

- `@file` 要的是击键事件 + 输入框附近一块可画布区；
- `open-in-vscode` 要的是工作区菜单弹出通知 + 塞入一项的能力；
- `sidebar-qa` 要的是选区变化事件 + 侧栏面板位；
- 主题插件要的是 token 变量的作用域。

DOM 只是这些语义请求在官方 Web 里的载体巧合。因此正确的问题不是"要不要运行官方前端"，而是：**能否伪造一个让插件信以为真的官方坐标系，而不渲染官方内容？**

---

## 2. 方案：Ghost Plane（幽灵平面）

> 一个全窗口、近乎全透明的 WKWebView 浮层，承载官方模块表 + 真实 SlotRegistry + 官方 CSS Token + 一棵由官方几何算法驱动的隐形骨架 DOM。插件以为自己活在官方页面里，实际悬浮在原生界面之上。官方内容（会话正文、侧栏列表、设置表单）依然 100% 由 SwiftUI 渲染。

### 2.1 四个核心机制

#### M1 隐形骨架（Ghost DOM）——结构真、内容空、几何真

mini-host 页面不放官方内容，放一棵同构骨架：菜单节点带 `[role=menu]`、会话节点带 `data-chat-anchor-key` / `data-streaming` / `data-chat-flow-kind`、composer 带 dock/overlay 挂载点。结构与契约属性由原生壳同步，内容留空。骨架几何直接复用项目已锁定的 `OfficialColumnLayoutFixtures`（官方 `columns.ts` 算法）与 theme tokens 计算——骨架与原生布局共享同一几何系，这是后续一切低成本对齐的前提。

#### M2 双形态锚点——沿依赖线切分，取消滚动锁步

锚点按物理属性分两类，各自采用最优承载：

- **固定锚点**（composer dock/overlay、侧栏面板、settings 区、浮层）：由全窗口幽灵平面承载，静态对齐，无同步问题；
- **滚动内容内锚点**（`turnTail`、`toolview` 卡片）：不做浮层，做**内联切片**——SwiftUI 消息尾部内嵌小 WKWebView（NSViewRepresentable），随原生滚动自然移动，同步问题从根上消失。

切片与主平面通过 BroadcastChannel + localStorage 共享 ctx 状态（同 origin 的 WKWebView 共享同一 WebContent 进程）。官方"单 document"语义只在文档级 DOM 操作（L3）中被真正依赖，而 L3 的目标全部位于固定层——这个拆分恰好沿依赖线切齐。

#### M3 单 ctx 保互操作

一个平面 = 一个 document = 一个 ctx。`sidebar-qa` 找得到 `betterSidebar` 注册的服务；marketplace 读得到桥注入的令牌；主题插件写的 `--dsw-*` 变量作用于平面内一切插件组件。官方生态"插件互相发现"的暗假设被完整保留——这是一切碎片化沙箱方案注定做不到的。

#### M4 事件桥——把原生输入翻译为 DOM 事件

原生 Composer 击键/粘贴/选区变化 → 桥接为骨架 DOM 上的合成事件。插件代码零改动。

### 2.2 平台 API 字典（自动转译）

兼容不照单全收：插件代码里每项 Web 平台 API 都是语义请求，逐项映射到 macOS 正牌等价物。**完备性按 API 契约面定义，不按当前插件使用频率定义**——读方向做了的，写方向同规范补齐。

| Web 平台 API | 原生等价物 | 备注 |
|---|---|---|
| `new Notification()` / `Notification.permission` | UNUserNotificationCenter + TCC 授权 | 救活纯通知类插件（0~5% → 95%+） |
| `document.visibilityState` | NSWindow occlusion / key 状态 | "仅后台提醒"语义成立 |
| `online`/`offline` | NWPathMonitor | |
| `navigator.clipboard` | NSPasteboard | |
| 粘贴图片（capture paste） | 粘贴板图像载荷 → 合成 ClipboardEvent | vision 类插件的核心入口，第一批实现 |
| `a[download]` / 文件选择 | NSSavePanel / NSOpenPanel | |
| 选区 Selection API **完整面**（含写方向） | 合成选区投影 ⇄ 原生 TextSelection 双向对称 | 见 §2.3 |
| KeyboardEvent | 按键分诊器（§2.4） | 按 KeyboardEvent 完整语义，非逐插件键位表 |
| Drag & Drop DataTransfer | NSDraggingSession ⇄ 合成 dragover/drop | 反向走 NSPasteboard |
| `fetch('/api/...')` 相对路径 | 同源 loopback 直达 host | **零转译**，架构白送 |
| `webServer.tapIndex` 令牌 | 构建 mini-host HTML 时依序重放全部 tapIndex 变换 | marketplace 写操作复活 |

### 2.3 选区投影（双向对称）

- **读方向**：原生 TextSelection 变化 → 幽灵平面创建定位到选区几何的透明投影节点（塞入真实选中文本）→ 程序化选中 → 插件 `getSelection()` 拿到货真价实的内容；
- **写方向**：插件在投影节点上的 `setSelection/addRange/removeAllRanges` 本就成功（真 DOM），缺的只是反映回原生——监听平面内 `selectionchange` → 经骨架自带的节点↔消息 ID 映射表换算 → 原生设置选区并滚动定位；
- 回环抑制用来源标记/版本号脏检查（经典镜像同步问题）；
- 映射表零新增成本：骨架本由原生同步生成，ID 对应天然存在。

明确放弃并记录为已知差异：插件要求宿主选区呈现其自定义视觉样式（官方 Web CSS 私货），原生以系统选区样式呈现，语义等价。

### 2.4 按键分诊器

焦点在原生 Composer、候选列表在平面的场景（`@file` 类）：`inputTriggers` 服务状态实时桥同步；open 期间导航键（↑↓Enter Esc Tab）转发为平面合成 KeyboardEvent，字符键留原生；pick 回写经桥翻译为原生 draft 替换（替代插件的 `execCommand('insertText')`）。

### 2.5 z 序与弹窗

平面跑两个实例：基础层（z 序贴内容）+ 浮层实例（窗口最高）。官方 `ui-primitives` 的 popover 本就 portal 到 body 高 z-index，天然落浮层实例。原生菜单打开时向平面发 blur 协调避让。

---

## 3. 三项架构决策

### D1 WebView 规则：全域禁令 → 三层白名单

原禁令的目的是防止 agent 构建本体时偷懒，不是产品原则。改为：

1. **红区（维持禁令）**：官方内容的渲染权——会话正文、侧栏列表、设置表单、工作区树。Web 不得渲染任何官方数据面。防偷懒红线原样保留，且更清晰：**官方内容渲染权不许交给 Web，插件渲染权必须交给 Web**。
2. **绿区（解除禁令）**：插件平面 target（Ghost Plane host）——唯一允许 WKWebView 之处，且固定锚点平面必须是单一共享实例。
3. **新增强制条款**：绿区内一切交互必须经原生桥保证键盘可达性 / VoiceOver / 权限语义（权限统一走 TCC），插件不得成为无障碍飞地。

既有 `NativeWebViewIsolationRuntimeTests` 门禁相应更新：红区断言不变；新增绿区 target 登记制（`swift package describe` target graph 允许清单）。

### D2 Profile：默认复用 `~/.dsh/profiles/web`

理由：(a) marketplace 与 `dsh plugin --profile web add` 等生态工具链硬编码 web profile，共享即插即用；(b) Host 本就是官方 payload，同 profile 使 sessions/settings/credentials 与官方 WebUI 完全互通；(c) 风险已有解——装载过滤一条规则（检测 manifest `runtime: host` 且接管 stdin 的 TUI/runtime 类，拒绝装入并提示独立 profile）。安全阀：settings 提供「使用独立 profile」开关，默认关。

### D3 Runtime：Attach > Adopt > Install 阶梯，不再强制捆绑 Node

1. **Attach**：探测活跃 `dsh web` 实例（loopback 发现）→ 直连。零 Node 需求，且避免双进程并发写同一 profile 存储（`HostLifecycleState.probingExternal` 已预留此意图，从边角推为主路径）；
2. **Adopt**：系统已有静态安装且版本恰为锁定 build → 用其拉起；
3. **Install**：都没有 → 首启引导下载锁定版到 app 容器（现 `repair-backend.sh` 流程改时机）。

红线不动：无论 runtime 来自哪里，只有命中 `SupportedHostBuilds.json` 锁定 build 才给 verified，否则维持 read-only 降级。fixtures 契约体系不为省体积让步。

---

## 4. 兼容责任边界

**契约面内 100%；契约面外明确不背。**

| 类别 | 处置 |
|---|---|
| 契约面内（标准 Web 平台 API + 官方扩展点） | Ghost Plane 全保，含写方向选区、完整键盘/拖拽语义 |
| 插件自身平台缺陷（如硬编码 `curl.exe`/`powershell.exe` 的 Windows-only） | 标注 `upstream-defect`，链接上游 issue，不做环境垫片 |
| 竞争性前端（TUI 接管宿主 stdio） | 非缺陷，正确用法即独立 profile；装载过滤提示 |
| 语义错配（插件管理"官方 web profile"之外的世界） | 功能归属重划：插件管理/主题切换等宿主本职由原生正经实现（T10.6/T11 已规划），消费同一数据源；兼容策略的健康终点是一部分插件变得不再必要 |
| 像素级复刻官方 Web 视觉的皮肤 | 原生骨架区无对应物——设计意图而非缺陷；token 作用域限于平面内 |

预期效果（18 插件实测基线 → 本方案）：中位兼容度 ~40% → **~90%+**；无一行为修改插件代码。

---

## 5. 验证路径

分四批，前两批是架构试金石：

1. **P0 试金石**：`dsh-review-loop`（最简依赖：一个 dock 槽位 + 2s 轮询 HTTP）验证固定锚点 + 内联切片 + 同源 fetch 全链路；`dsh-open-in-vscode`（纯 legacy DOM 路径：`[role=menu]` 文案反查 + body MutationObserver）验证骨架 DOM 仿真保真度。这两个打通，架构立住。
2. **P1 高价值桥**：粘贴图片链路（vision 类命根子）、Notification shim、按键分诊器（`at-file`）。
3. **P2 互操作**：`better-sidebar` 服务注册 + `sidebar-qa` 消费（验证单 ctx 互操作）、选区投影双向、主题 token 注入。
4. **P3 收尾**：marketplace（tapIndex 重放 + 共享 profile 验证）、`dsh-web-ui` 家族逐包清点。

每批的验收证据沿用项目既有纪律：运行态行为测试（禁止源码文本对暗号）、可证伪性、同条件官方/原生对照。

### 骨架契约防漂移

骨架的 selector/契约属性清单纳入既有 spec-drift 门禁：CI 跑官方锁定 build 页面抓取契约快照，与骨架定义 diff，漂移即红。维护成本被现有 OfficialUISpec 流程吸收。

---

## 6. 对现有任务体系的影响

| 原任务 | 处置 |
|---|---|
| T11.1 NativeUIManifest / T11.2 NativeSchemaForm / T11.3 SwiftAdapterRegistry | **保留**，角色调整为"精品快车道"：愿意做原生适配的插件享受零桥接开销 |
| T11.4 分流器 | 保留，末级兜底从"单卡片沙箱"改为"Ghost Plane" |
| T11.5 mini-host 卡片容器 | **改写**为 Ghost Plane host（见本文档 §2）；settings 卡片退化为固定锚点的一个特例 |
| T11.6 卡片自适应视觉融合 | 并入 Ghost Plane 固定锚点形态 |
| T11.7 禁止侵入核心骨架 | 保留并强化为红区/绿区白名单（D1） |
| T12.7 安全审查 | 扩展：绿区 target 登记、tapIndex 重放的 HTML 净化、平面内导航阻断、TCC 权限语义 |

新增任务族（提案批准后在 TODO 展开）：GP-1 骨架 DOM 生成器与契约快照门禁；GP-2 固定锚点平面（模块表 + SlotRegistry + token 注入）；GP-3 内联切片与 BroadcastChannel ctx 镜像；GP-4 事件桥四件套（键盘/粘贴/选区/拖拽）；GP-5 平台 API 字典第一批（Notification/clipboard/visibility/download）；GP-6 profile 共享与装载过滤；GP-7 runtime Attach/Adopt/Install 阶梯。

## 7. 开放问题

1. 多窗口（多会话窗）是否共享同一固定锚点平面实例（倾向共享，省内存且符合单 ctx 语义，需验证跨窗焦点协调）；
2. 幽灵平面内存水位（预估常驻 +50~100MB）在低端机上的降级策略（平面按需冷启动？）;
3. `NativeUIManifest` schema 是否需要为"来自 Ghost Plane 的自动发现"增加一个 `autoDetected` 来源标记，以便设置页区分精品适配与兜底承载；
4. Attach 模式下外部 host 版本高于锁定 build 时的 UX（维持 read-only 或提示升级 app 支持矩阵）。

---

## 附录 A：18 插件实证结论摘要

| 插件 | 形态 | 原设计直接安装 | Ghost Plane 预期 | 主要增量来源 |
|---|---|---|---|---|
| dsh-orchestrator | toolkit | 95~100% | 100%* | worker 流视图（原生端路线图） |
| dsh-plugin-anydoc | toolkit | 95~100% | 100% | — |
| dsh-custom-tool | hybrid | 55~75% | 100% | 设置页特例成型 |
| modlens | hybrid | 70~85% | 95%+ | 粘贴桥 |
| dsh-vision-toolkit | hybrid | 55~70% | 95% | toolview 切片 + artifact 同源直载 + 粘贴桥 |
| dsh-review-loop | hybrid | 40~60% | 100% | dock 锚点 |
| dsh-at-file | hybrid | 20~35% | 95% | inputTriggers 桥 + 按键分诊器 |
| dsh-open-in-vscode | hybrid | 0~10% | 90%+ | 骨架 `[role=menu]` 契约 |
| dsh-sidebar-qa | hybrid | 0~10% | 90% | betterSidebar 服务在场 + 选区投影 |
| dsh-web-ui 家族 | hybrid×16 | 30~45% | 85%+ | conversation./sidebar. 槽位全体复活 |
| dsh-theme-plugin | theme | 35~50% | 95% | token 全量注入平面 |
| DSH-Plugins-Marketplace | hybrid | 20~40% | 90%+ | 共享 profile + tapIndex 重放 |
| dsh-web-ui-notify | 纯 Web | 0~5% | 95%+ | Notification → UNUserNotificationCenter |
| dsh-usage-stats | hybrid | 65~80% | upstream-defect* | 余额查询硬编码 Windows，不背 |
| dsh-opencodego-usage | hybrid | 10~20% | upstream-defect* | 同上 |
| dsh-tianshu-tui | tui | 0~10%（同 profile） | 独立 profile 正确用法 | 装载过滤提示 |
| dsh-explorer | ui-panel | 30~50%* | 85%+ | 侧栏面板锚点 |
| dsh-opencodego-usage 之外的 Windows 缺陷观察 | — | — | — | 与客户端形态无关 |

\* 标注项为推断或非本架构责任，详见分析记录。
