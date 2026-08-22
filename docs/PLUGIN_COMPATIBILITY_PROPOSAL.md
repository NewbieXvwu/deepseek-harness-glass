# 专项提案：第三方插件全兼容运行时（Ghost Plane 幽灵平面）v3

| | |
|---|---|
| 状态 | 草案 v3（吸收二次外部评审；按"开源工具立场"收敛过度设计） |
| 取代 | 原「渐进双轨制 + `PluginWebHost` 单卡片沙箱」设计（TODO T11 系列 v1） |
| 官方基准 | `deepseek-ai/deepseek-harness` `0.1.1-rc.1`（commit `528c682e`）；契约红线仍以 `SupportedHostBuilds.json` 锁定 build 为 verified 判据 |
| 证据基础 | 43 个社区插件源码实读分析（初版 18 + 两次外部评审补充 25），全部结论带文件:行号级证据；官方槽位全集与装载契约经独立分析交叉验证 |
| 修订记录 | v1→v2：① M2 单一主 document；② T0–T4 分级；③ 安全模型；④ 门禁扩展；⑤ 行为闭环验证；⑥ 并入 12 样本；⑦ 路径修正。**v2→v3**：① 砍掉 grant 会话/窗口绑定、指纹判定、白名单、compat.
json、发布口径改名等家长式设计（开源工具立场：兼容是 Ghost Plane 的义务，不是插件的义务）；
② Shadow Host 服务图表述去仪式化，保留其物理前提；③ 事务回滚边界诚实化（补不了的不假装原子）；④ 并入二次评审的 13 样本并剥离 TUI/remote/extension 出 UI 统计 |

---

## 1. 背景与动机

对 43 个真实生态插件的实证分析表明：按原双轨制设计直接安装，兼容度两极分化——纯 Host 工具类 95~100%，而任何依赖 client 半区 UI 承载的插件大面积静默失效（0~45%）。
失效不是工程量问题，而是原「单卡片沙箱」模型的结构性缺陷：它假设插件 UI 可以被拆成孤立卡片，但生态的现实是插件深度耦合官方页面的**槽位位置、服务注入与文档级 DOM 契约**，部分插件更进一步要求**完整会话视图与宿主数据面**。

### 1.1 四类失效根因

1. **装载语义全有或全无**。client entry 的 `inject` 声明任一服务缺失 ⇒ 整个 fiber 停在 pending、不激活（`packages/client/web/src/boot.ts:148-156`）。
   原生壳内不存在 `inputTriggers`、`betterSidebar` 等服务时，插件整体静默消失而非降级。
2. **槽位承载面结构性缺失**。官方槽位是 Web 页面内的 React 插槽注册表（`packages/client/runtime/src/client/slots.ts:93` SlotRegistry）。`conversation.input.
   dock/overlay/right`、`sidebar.*`、`tool.call.toolview`、`conversation.chat.turnTail` 全部依赖官方 Web 的组件树位置，原生壳无渲染点。
3. **文档级 DOM 侵入在隔离环境空转**。`querySelectorAll('[role="menu"]')`、body 级 `MutationObserver`、`document.body.appendChild` 浮层、`window.
   getSelection()` 划词——iframe 沙箱与宿主 DOM 互相隔离，此类能力全部静默失效。
4. **宿主数据与服务面缺失**。除 DOM 坐标外，部分插件要的是**会话/工作区数据投影、fence/streaming 状态、命令 UI、OAuth 流程**——这不是渲染问题，是数据模型问题；空洞骨架与隔离容器均无法提供。

### 1.2 关键洞察

没有任何插件想要"官方的像素"，它们想要的是**官方的坐标、事件与数据**：

- `@file` 要的是击键事件 + 输入框附近一块可画布区 + 会话路径索引；
- `open-in-vscode` 要的是工作区菜单弹出通知 + 塞入一项的能力；
- `sidebar-qa` 要的是选区变化事件 + 侧栏面板位 + 会话消息内容；
- 主题插件要的是 token 变量的作用域；
- 会话视图类插件要的是完整会话模型的投影。

DOM 只是这些语义请求在官方 Web 里的载体巧合。因此正确的问题不是"要不要运行官方前端"，而是：**能否伪造一个让插件信以为真的官方坐标系与数据上下文，而不渲染官方内容？** 答案需要分能力层级给出（见 §4），而非一句"全兼容"。

---

## 2. 方案：Ghost Plane（幽灵平面）

> 一个全窗口、近乎全透明的 WKWebView 浮层，承载官方模块表 + 真实 SlotRegistry + 官方 CSS Token + 一棵由官方几何算法驱动的隐形骨架 DOM + 经由 typed bridge 的宿主数据面。插件以为自己活在官方页面里，
> 实际悬浮在原生界面之上。官方内容（会话正文、侧栏列表、设置表单）依然 100% 由 SwiftUI 渲染。
> 
> 

### 2.1 核心机制

#### M1 隐形骨架（Ghost DOM）——结构真、内容空、几何真

mini-host 页面不放官方内容，
放一棵同构骨架：菜单节点带 `[role=menu]`、会话节点带 `data-chat-anchor-key` / `data-streaming` / `data-chat-flow-kind`、composer 带 dock/overlay 挂载点。


结构与契约属性由原生壳同步，内容留空。
骨架几何直接复用项目已锁定的 `OfficialColumnLayoutFixtures`（官方 `columns.ts` 算法）与 theme tokens 计算——骨架与原生布局共享同一几何系，这是后续一切低成本对齐的前提。

骨架不是通用兼容的地基，而是 **T3 Legacy DOM 适配层的承载物**（见 §4）：对其视（selector/observer）的仿真尽力而为，能匹配就匹配、匹配不了如实报错，不承诺通配。

#### M2 单一主 document——滚动同步退化为一个标量

**全部锚点（固定锚点与滚动内容内锚点）同住一个 WKWebView 主 document**：插件组件绝对定位在骨架坐标处；原生会话流滚动时，仅向平面传递 `scrollOffset` 标量，平面内部自行 transform 内容。
惯性滚动期间偶发一帧滞后表现为插件卡片的轻微拖影（视觉瑕疵），换取互操作、portal、事件冒泡与 DOM 身份完整保真。


> **v1 废弃设计记录**：v1 曾设计"滚动内容锚点用独立内联切片（NSViewRepresentable WKWebView）+ BroadcastChannel 镜像 ctx"。
> 评审正确指出该设计自相矛盾：BroadcastChannel/localStorage 可同步**数据**，
> 但无法共享**服务对象引用**（函数不可序列化）——跨 document 的插件（如 `sidebar-qa` inject `betterSidebar` 服务）将死于 hard injection gate。
> 单 document 是"真实 slot + 互操作"的唯一可保证形态；滚动同步成本由标量通道承担，不属于架构缺陷。
> 

#### M3 单 ctx 保互操作

一个平面 = 一个 document = 一个 ctx。`sidebar-qa` 找得到 `betterSidebar` 注册的服务；marketplace 读得到桥注入的令牌；主题插件写的 `--dsw-*` 变量作用于平面内一切插件组件。
官方生态"插件互相发现"的暗假设被完整保留——由于 M2 回归单 document，此承诺**全局成立**，不再有切片豁免。

#### M4 事件桥——把原生输入翻译为 DOM 事件

原生 Composer 击键/粘贴/选区变化 → 桥接为骨架 DOM 上的合成事件。插件代码零改动。

### 2.2 平台 API 字典（自动转译 + 权限标注）

兼容不照单全收：插件代码里每项 Web 平台 API 都是语义请求，逐项映射到 macOS 正牌等价物。**完备性按 API 契约面定义，不按当前插件使用频率定义**——读方向做了的，写方向同规范补齐。

| Web 平台 API | 原生等价物 | 授权方式 | 备注 |
|---|---|---|---|
| `new Notification()` / `Notification.permission` | UNUserNotificationCenter | **系统 TCC 首调弹窗** | 救活纯通知类插件（0~5% → 95%+） |
| `document.visibilityState` | NSWindow occlusion / key 状态 | 随装载授予 | "仅后台提醒"语义成立 |
| `online`/`offline` | NWPathMonitor | 随装载授予 | |
| `navigator.clipboard` | NSPasteboard | 随装载授予 | macOS 对写入无系统提示，风险天然低 |
| 粘贴图片（capture paste） | 粘贴板图像载荷 → 合成 ClipboardEvent | 随装载授予 | vision 类核心入口，第一批实现 |
| `a[download]` / 文件选择 | NSSavePanel / NSOpenPanel | **用户交互即授权** | 模态面板，用户亲手选择即授权行为 |
| 选区 Selection API 完整面（含写方向） | 合成选区投影 ⇄ 原生 TextSelection 双向对称 | 随装载授予 | 见 §2.3 |
| KeyboardEvent | 按键分诊器（§2.4） | 随装载授予 | 按完整语义，非逐插件键位表 |
| Drag & Drop DataTransfer | NSDraggingSession ⇄ 合成 dragover/drop | 随装载授予 | 反向走 NSPasteboard |
| OAuth / 打开系统浏览器 | 系统浏览器跳转 | **每次跳转前确认 URL** | 唯一真需自定义确认项 |
| `fetch('/api/...')` 相对路径 | 同源 loopback 直达 host | 随装载授予 | **零转译**，架构白送 |
| `webServer.tapIndex` 令牌 | 构建 mini-host HTML 时依序重放 | 共享 profile 前提下等价于官方页面 | 重放内容先净化（本质是把官方页面同等注入搬进平面，非新增信任） |

### 2.3 选区投影（双向对称）

- **读方向**：原生 TextSelection 变化 → 幽灵平面创建定位到选区几何的透明投影节点（塞入真实选中文本）→ 程序化选中 → 插件 `getSelection()` 拿到货真价实的内容；
- **写方向**：插件在投影节点上的 `setSelection/addRange/removeAllRanges` 本就成功（真 DOM），
  缺的只是反映回原生——监听平面内 `selectionchange` → 经骨架自带的节点↔消息 ID 映射表换算 → 原生设置选区并滚动定位；
- 回环抑制用来源标记/版本号脏检查（经典镜像同步问题）；
- 映射表零新增成本：骨架本由原生同步生成，ID 对应天然存在。

明确放弃并记录为已知差异：插件要求宿主选区呈现其自定义视觉样式（官方 Web CSS 私货），原生以系统选区样式呈现，语义等价。

### 2.4 按键分诊器

焦点在原生 Composer、候选列表在平面的场景（`@file` 类）：`inputTriggers` 服务状态实时桥同步；
open 期间导航键（↑↓Enter Esc Tab）转发为平面合成 KeyboardEvent，字符键留原生；pick 回写经桥翻译为原生 draft 替换（替代插件的 `execCommand('insertText')`）。


### 2.5 z 序与弹窗

平面跑两个实例：基础层（z 序贴内容）+ 浮层实例（窗口最高）。官方 `ui-primitives` 的 popover 本就 portal 到 body 高 z-index，天然落浮层实例。原生菜单打开时向平面发 blur 协调避让。

---

## 3. 三项架构决策

### D1 WebView 规则：全域禁令 → 红/绿区白名单 + T4 受管容器

原禁令的目的是防止 agent 构建本体时偷懒，不是产品原则。改为：

1. **红区（维持禁令）**：官方内容的渲染权——会话正文、侧栏列表、设置表单、工作区树。Web 不得渲染任何官方数据面。防偷懒红线原样保留，且更清晰：**官方内容渲染权不许交给 Web，插件渲染权必须交给 Web**。
2. **绿区（解除禁令）**：插件平面 target（Ghost Plane host）——唯一允许 WKWebView 之处，且固定锚点平面必须是单一共享实例。
3. **T4 受管容器（opt-in）**：用户显式安装的第三方全页插件（`conversation.view`、完整设置页、iframe 子应用）经原生导航容器内受管 Web surface 承载。产品决策记录：红区约束的是**本应用自身实现**不许偷懒，
   用户主动安装的第三方全页插件不属于"本应用渲染官方内容"，故不违约；此类容器不计入"主界面原生"承诺范围，且必须实现尺寸/焦点/权限/生命周期协议。
4. **新增强制条款**：绿区与 T4 容器内一切交互必须经原生桥保证键盘可达性 / VoiceOver / 权限语义，插件不得成为无障碍飞地。

既有 `NativeWebViewIsolationRuntimeTests` 门禁相应更新：红区断言不变；新增绿区/T4 target 登记制（`swift package describe` target graph 允许清单）。

### D2 Profile：默认复用 `~/.dsh/profiles/web` + 运行时授权安全模型

身份共享与能力控制分离：

- **身份域（默认共享）**：复用 web profile 使 marketplace 与 `dsh plugin --profile web add` 等生态工具即插即用，sessions/settings/credentials 与官方 WebUI 完全互通。
  安全阀：settings 提供「使用独立 profile」开关，默认关。
- **能力域（运行时授权）**：见 §3.3 安全模型。信任边界在安装时刻，桥能力为同插件 Host 半区的严格子集，不构成新攻击面；运行时只做浏览器式初次调用授权。
- **装载过滤**：竞争 stdio 的 runtime/TUI 类拒绝装入共享 profile 并提示独立 profile。

### D3 Runtime：Attach > Adopt > Install 阶梯，不再强制捆绑 Node

1. **Attach**：探测活跃 `dsh web` 实例（loopback 发现）→ 直连。零 Node 需求，且避免双进程并发写同一 profile 存储（`HostLifecycleState.probingExternal` 已预留此意图）；
2. **Adopt**：系统已有静态安装且版本恰为锁定 build → 用其拉起；
3. **Install**：都没有 → 首启引导下载锁定版到 app 容器（现 `repair-backend.sh` 流程改时机）。

红线不动：无论 runtime 来自哪里，只有命中 `SupportedHostBuilds.json` 锁定 build 才给 verified，否则维持 read-only 降级。fixtures 契约体系不为省体积让步。

### 3.3 安全模型：安装时刻即信任边界

> **核心立场**：DSH 插件的信任模型是 npm 包模型——`dsh plugin add github:xxx` 即授予该插件在 Host 进程中执行任意 Node 代码的全权（读文件、开网络、碰凭据存储、spawn 子进程）。
> Ghost Plane 的 client 桥能力相对**同一个插件**的 Host 半区能力是严格子集，不构成新的攻击面。
> 用浏览器扩展的沙箱威胁模型套 DSH 插件属于错配——这不是我们该修的问题，修它也修不了。

因此运行时安全采用**最轻的一致化**：

1. **初次调用授权（浏览器式）**：`PermissionBroker` 按 `(pluginId, capability)` 记忆 granted/denied；插件首次调用需授权的能力时，弹原生对话框（带插件名与能力说明），选择被记住。
   不绑会话/窗口/时效——这是桌面 app 不是 iOS 企业环境，永久记忆 + 事后可撤销已经足够。
2. **大头由系统兜底**：通知走 UNUserNotificationCenter 的 TCC 首调弹窗；Save/OpenPanel 为用户交互即授权；剪贴板写风险天然低。**唯一自定义确认项**：跳转系统浏览器的外链/OAuth（展示目标 URL）。
   settings 仅提供**事后查看与撤销**（像浏览器站点权限页），不设预授权入口。
3. **profile 变更类操作的回滚边界**（marketplace 安装/更新/卸载）：可回滚的部分（patch/配置）做 staged commit 回滚；
   不可回滚的部分（npm install script 的副作用、已下载依赖、运行中 module graph）**诚实标注"补偿失败，需人工处理"**，不假装原子——补不了的事不吹。
4. 明确的边界声明：为浏览器编写但含恶意 Host 代码的插件，其威胁在**安装时刻**已成事实，任何 client 层桥都无法逆转——那不是兼容层的职责。

---

## 4. 分级能力模型（T0–T4）——取代"契约面内 100%"表述

兼容承诺按能力层级定义，每层有独立的承载方式、成功标准与统计口径：

| 层级 | 含义 | 承载方式 | 成功标准（不是"加载成功"） |
|---|---|---|---|
| **T0 Host-only** | tools / CLI / RPC / provider / worker | 官方 host runtime | 工具调用与结果回传闭环；**不计入 UI 兼容统计** |
| **T1 Native adapter** | 有 `NativeUIManifest` / `SwiftAdapter` | SwiftUI 精品快车道 | 原生交互 + Liquid Glass 质感复刻 |
| **T2 Contract Web Surface** | 标准 slots + 版本化 typed bridge | 单一主 document 内的插件 UI 运行时 | slot 挂载、服务注入、行为用例、无障碍、卸载清理通过 |
| **T3 Legacy DOM adapter** | selector / observer / body 注入 | 主 document 骨架 DOM（尽力兼容） | **尽力跑，不设门槛**：能匹配就匹配，匹配不了就如实报错，不搞指纹判定/白名单/风险标识，
不替用户决定 |
| **T4 Full View / Sandbox app** | `conversation.view`、完整设置页、iframe 子应用 | 原生导航容器内受管 Web surface | 尺寸/焦点/权限/生命周期协议 + 行为用例通过 |

**统计口径**：兼容度按层级内成员计算。**不搞认证**——插件装上能跑就是能跑，跑不了就把坏在哪如实显示（报错信息、缺失服务、loading 卡住原因），由用户决定去留。数字只是对"哪些大概率能活"的事前估计，验证以 §5 行为测试为准。

**与 v1 表述的关系**：v1 的"契约面内 100% / 中位 90%+"改为分层重新表述——T0 与 T2 为承诺层级（可测试、可验收），T3/T4 明示尽力/受管语义，长尾形态不再被头部门槛掩盖。

---

## 5. 验证路径（行为闭环）

分四阶段，每阶段以**行为断言**为通过证据，不以"源码中出现某 selector"或"插件加载成功"代替：

| 阶段 | 代表插件 | 必过行为断言 |
|---|---|---|
| **P0 激活与单 document** | `dsh-review-loop`、`dsh-open-in-vscode`、`dsh-visualize` | module graph 正确激活（inject 服务齐备）；dock/menu 契约命中；RPC 交互闭环；
卸载后无 observer/样式残留；
惯性滚动下卡片无可见错位 |
| **P1 高价值桥** | `dsh-at-file`、`dsh-vision-toolkit`、`dsh-web-ui-notify` | @ 全键盘闭环（↑↓/Enter/Esc）；贴图即析；系统通知 TCC 首调弹窗与送达 |
| **P2 互操作与选区** | `DSH-better-sidebar` + `dsh-sidebar-qa`、`dsh-theme-plugin` | 跨插件服务发现（`betterSidebar`）成功；划词投影双向一致；token 注入换肤生效且原生骨架区不受影响 |
| **P3 装配与边界** | `DSH-Plugins-Marketplace`、`dsh-usage-stats` | tapIndex 重放后写操作可用；profile 变更可回滚部分验证回滚、不可回滚部分（安装脚本副作用）如实标注；
`upstream-defect`（Windows-only）标注清晰呈现 |

全部阶段使用同一锁定官方 build、可复现插件提交、行为级断言、失败分类与性能/内存数据。

### 骨架契约防漂移

骨架的 selector/契约属性**以及 SlotMap、服务声明、module manifest** 纳入既有 spec-drift 门禁：CI 跑官方锁定 build 页面抓取契约快照，与骨架定义 diff，漂移即红。
仅快照 selector 不足以捕获 slot/注入签名变化——DOM 看似一致时插件仍可能死于 injection gate。
维护成本被现有 OfficialUISpec 流程吸收。

---

## 6. 对现有任务体系的影响

| 原任务 | 处置 |
|---|---|
| T11.1 NativeUIManifest / T11.2 NativeSchemaForm / T11.3 SwiftAdapterRegistry | **保留**，角色定为 T1 精品快车道 |
| T11.4 分流器 | 保留，路由改为 T0–T4 分层（SwiftAdapter ➔ NativeUIManifest ➔ Ghost Plane ➔ Host-Only） |
| T11.5 Ghost Plane host | 保留（固定锚点平面 + 骨架 + typed bridge 前置服务注入） |
| T11.6 | 重写：单 document + 滚动标量同步 + 事件桥（原内联切片设计废弃） |
| T11.7 红/绿区门禁 | 保留并强化为红/绿区 + T4 受管容器登记 |
| T11.8 契约防漂移 | 扩展：快照范围含 SlotMap / 服务声明 / module manifest |
| T12.7 安全审查 | 更新为安装时刻信任模型 + PermissionBroker + TCC + 回滚边界审查（可回滚 staged / 不可回滚如实标注） |

新增任务族（GP）：GP-1 骨架 DOM 生成器；
GP-2 主 document host + typed bridge 前置；GP-3 滚动标量同步引擎；GP-4 事件桥四件套；GP-5 平台 API 字典（含 PermissionBroker）；GP-6 profile 共享与装载过滤；GP-7 runtime 阶梯。
另增 GP-8 PermissionBroker 授权界面（首调弹窗 + 事后撤销页）。

## 7. 开放问题

1. 多窗口（多会话窗）是否共享同一固定锚点平面实例（倾向共享，省内存且符合单 ctx 语义，需验证跨窗焦点协调与滚动标量路由）；
2. 幽灵平面内存水位（预估常驻 +50~100MB）在低端机上的降级策略（平面按需冷启动？）；
3. `NativeUIManifest` schema 是否需要为"来自 Ghost Plane 的自动发现"增加 `autoDetected` 来源标记；
4. Attach 模式下外部 host 版本高于锁定 build 时的 UX（维持 read-only 或提示升级 app 支持矩阵）；
5. 滚动标量同步在 120Hz ProMotion 下的实际帧率缺口需要 P0 实测（开放为验证项而非设计前提）。

---

## 附录 A：43 插件实证矩阵

**样本构成**：本提案初版 18 个（`dsh-plugin` topic 头部、覆盖全形态，两路独立交叉验证）+ 一次评审补充 12 个 + 二次评审补充 13 个。所有数字为**事前估计**（"大概率能活"），不是认证；最终以 §5 行为测试为准，活不了就把坏在哪如实显示，
由用户决定去留。


| 插件 | 形态 | 判级 | 预期（事前估计） | 主要增量来源 / 说明 |
|---|---|---|---|---|
| dsh-orchestrator | toolkit | T0 | 100% | 纯 Host；worker 流视图为原生端路线图 |
| dsh-plugin-anydoc | toolkit | T0 | 100% | 纯 Host |
| dsh-plugin-bridge (评审样本) | host CLI/RPC | T0 | 100% | 问题域不在 UI 平面 |
| dsh-plugin-cc (评审样本) | host/CLI | T0 | 100% | 问题域不在 UI 平面 |
| dsh-custom-tool | hybrid | T2 | 95~100% | 设置页特例 + 模型闭环 |
| dsh-review-loop | hybrid | T2 | 95~100% | dock 锚点 + 轮询 HTTP |
| dsh-visualize (评审样本) | hybrid | T2 | 90%+（优先实测） | 标准 slot 型，最贴合 Ghost Plane |
| dashi-taskboard (二次评审样本) | hybrid | T2 | 高（条件性） | sidebar.footer.action + host webServer 路由 + 同源 fetch；
需 Shadow Host 提供 renderer/slot props |
| modlens | hybrid | T2 | 95%+ | 粘贴桥 |
| dsh-vision-toolkit | hybrid | T2 | 95% | toolview + artifact 同源直载 + 粘贴桥 |
| dsh-at-file | hybrid | T2 | 95% | inputTriggers 桥 + 按键分诊器 |
| dsh-theme-plugin | theme | T2（平面内）/ 换肤边界见 §4 注 | 95% | token 全量注入平面；原生骨架区换肤不生效是物理事实，如实呈现 |
| dsh-web-ui-notify | 纯 Web | T2 | 95%+ | Notification → UNUserNotificationCenter |
| dsh-sidebar-qa | hybrid | T2 | 90% | betterSidebar 服务在场 + 选区投影 |
| dsh-open-in-vscode | hybrid | T3 | 80~90%（尽力） | 骨架 `[role=menu]` 契约；slot 主路径缺失时走 legacy |
| dsh-web-ui 家族 | hybrid×16 | T2/T3 | 85%+ | conversation./sidebar. 槽位复活；DOM shim 为 T3 |
| DSH-Plugins-Marketplace | hybrid | T3 | 80%+ | 共享 profile + tapIndex 重放；profile 变更回滚边界见 §3.3 |
| dsh-genui (评审样本) | hybrid | T2/T3 | 中 | fence registry / DOM 回退双通道；需真实消息/fence 数据 |
| dsh-plugin-subscriptions (评审样本) | hybrid | T2 | 中 | OAuth/popup、commandUi、媒体 toolview 需 bridge |
| dsh-plugin-mineru (评审样本) | hybrid | T2 | 中 | 持久设置、文件选择 |
| dsh-vision-router (二次评审样本) | hybrid | T2 | 部分可行 | settings/toolview slot 走 T2、图片桥有帮助；loader monkey patch 不保证 |
| dsh-im (二次评审样本) | hybrid | T2 | 部分可行 | settings.plugins.tab 可承载；凭据/QR/多通道事务是 Host 协议面 |
| dsh-context (二次评审样本) | hybrid | T4 | 部分可行 | conversation.view + session projection + 历史分页需 Shadow Host 数据面 |
| dsh-agent-teams (二次评审样本) | hybrid | T4 | 部分可行 | shell overlay + DAG + session list/open；需 session event ABI |
| dsh-usage-plugin (评审样本) | hybrid | T4 | 中 | 两个 conversation view + Canvas/download |
| dsh-deepseek-design (评审样本) | hybrid | T4 | 中 | conversation.view、iframe→draft 回写 |
| dsh-plugin-agent-workflow (评审样本) | hybrid | T4 | 低 | 完整会话数据投影 + 导航视图（产品决策项） |
| dsh-openpencil (二次评审样本) | hybrid | T4 | 条件性可行 | toolview 内容为 CanvasKit/WASM + 跨源 iframe；受管容器需 origin/CSP/dirty-close 协议 |
| dsh-sidebar-qa 类长尾（session-delete 等，评审样本） | hybrid | T3 | 中偏低（尽力） | 真实列表/menu 生命周期要求高，slot 主路径优先 |
| dsh-ads (二次评审样本) | hybrid | T3 | 低（尽力） | body portal + 全局 DOM 是保真度压力测试；骨架尽力匹配，匹配不了如实报错 |
| dsh-plugin-workshop (评审样本) | hybrid | T3 | 中偏低 | 原生新会话按钮/侧栏 class 不在骨架承诺内 |
| **非 UI 平面问题域（不计入 UI 兼容统计）** | | | | |
| dsh-tianshu-tui | tui | 独立 profile | 不适用 | 竞争 stdio，正确用法即独立 profile |
| dsh-TUI (二次评审样本) | tui | 独立 profile | 不适用 | 同上；注意与 dsh-tianshu-tui 是不同仓库 |
| dsh-browser (二次评审样本) | 浏览器扩展 | 独立 | 不适用 | Host-to-extension 安全协议，问题域在扩展侧 |
| dsh-pocket (二次评审样本) | 远程代理 | 独立 | 不适用 | 把完整 Web UI 代理给移动端，需要 remote-web 模式而非 UI 平面 |
| dsh-market (二次评审样本) | profile 管理 | 控制面 | 不适用 | 插件市场控制面，问题是事务/锁/HMR 而非渲染 |
| dsh-deep-whale (二次评审样本) | 全局主题 | T1 换肤边界 | 低 | CSS 重写官方整页；平面内 CSS 影响不了 SwiftUI 正文——用受支持 token 映射，不承诺穿透 |
| DSH-Transparent-UI-Plugin (二次评审样本) | 全局主题 | T1 换肤边界 | 低 | 同上；WebGL/canvas 部分标 Web-only |
| dsh-usage-stats | hybrid | T0+T3 | upstream-defect | 余额查询硬编码 Windows 进程，不背 |
| dsh-opencodego-usage | hybrid | T0+T3 | upstream-defect | 同上 |
| dsh-explorer | ui-panel | T2 | 85%+ | 侧栏面板锚点 |

**样本说明（实话版）**：头部热门样本偏 standard-slot 型；两次评审补充的长尾样本暴露了更多依赖面（fence registry、conversation.view、OAuth、commandUi、Canvas/WASM、远程代理）。整体约 43 个构成生态画像。
TUI、远程 full-web proxy、浏览器扩展、profile 管理控制面等**不属于 UI 平面问题域**，
从 UI 兼容统计中剥离是事实归类而非口径粉饰。主题类能映射受支持 token 的走换肤，穿不透 SwiftUI 的部分如实标 Web-only。

---

## 附录 B：v1 → v3 修订记录

**v1 → v2**（吸收一次评审）：
1. **M2 单 document**：废弃内联切片与 BroadcastChannel ctx 镜像（评审否决：服务对象引用不可跨 document 共享，硬 injection gate 会杀死跨插件互操作）；滚动同步改为单标量传递；
2. **T0–T4 分级模型**：取代"契约面内 100% / 中位 90%+"表述；统计口径分层；
3. **安全模型**：改为安装时刻信任边界（npm 包模型）；浏览器式初次调用授权；系统 TCC 兜底大头；settings 仅事后撤销；`tapIndex` 重放限定受控兼容通道；
4. **门禁扩展**：防漂移快照含 SlotMap / 服务声明 / module manifest；
5. **验证改写**：P0–P3 改为行为闭环断言；
6. **样本并入**：12 个评审补充样本入附录 A；
7. **路径修正**：`runtime/src/client/slots.ts` → `packages/client/runtime/src/client/slots.ts`。

**v2 → v3**（吸收二次评审；按开源工具立场收敛过度设计）：
1. **砍掉家长式机制**：grant 会话/窗口/时效绑定、DOM 指纹判定、白名单、`dsh-plugin-compat.json`、发布口径改名——全部移除。立场：兼容是 Ghost Plane 的义务，不是插件的义务；用户装了自己决定，坏就如实报错，
   不做"判定/拦在门外/指望插件迁就我们"。
2. **Shadow Host 服务图保留为物理前提**（官方 boot 的 hard injection gate 使然），但去仪式化：它是原生已有能力（transport/projection/settings）的 Web 侧 ABI 投影，不是重写官方 client；
   不叫"最小但真实的 Shadow Host ABI"这种发布会词。
3. **事务回滚边界诚实化**：可回滚（patch/配置）做 staged commit；不可回滚（install script 副作用、已下载依赖、运行中 module graph）如实标"补偿失败，需人工处理"，不假装原子。
4. **T3 降门槛**：尽力跑、不设门槛、失败如实呈现；删"单插件指纹 + 风险标识"。
5. **样本并入 13 个二次评审样本**（总 43），TUI/远程 full-web proxy/浏览器扩展/profile 管理控制面从 UI 兼容统计剥离（事实归类）；主题类改"受支持 token 换肤 + web-only 如实标注"，不安排正式适配器工程。