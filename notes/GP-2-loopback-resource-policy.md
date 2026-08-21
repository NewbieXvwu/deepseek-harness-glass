# GP-2：固定锚点平面同源资源策略

**状态：** 已实现纯 Core `GhostPlaneLoopbackPolicy`、Core XCTest 与 Linux Swift 回归；本 GP-2 子阶段尚未建立 WebKit host，因此整体任务仍未勾选。

## 1. 官方来源与最小安全结论

锁定官方 `ClientModuleSystem` 的默认 bundle transport 通过一个外部 classic script 加载 `row.url`；加载后必须经 `window.__ModuleLoader__.load` 注册到已知 module table，否则直接报错。[1] 这说明 Ghost Plane 不能把“能导航到某 URL”误解为“可安全 materialize module”：资源 origin、module table 和 injection lifecycle 都是独立契约。

GP-2 的第一阶段因此先建立**纯资源准入层**。它不执行 loader、不运行 plugin code、也不提供 bridge；其唯一职责是让将来的 `WKNavigationDelegate` 在网络或导航实际发生前，以同一纯函数判断是否应拒绝。

| 请求条件 | 决策 | 原因 |
|---|---|---|
| `http://127.0.0.1:<origin-port>/plugins/<registered-id>/…` | allow | 已登记 plugin 的同源资源目录。 |
| HTTPS、file、data、javascript 或任意非 HTTP scheme | deny | Ghost Plane 不承载外网或本地文件导航。 |
| 非 `127.0.0.1`、端口不匹配、URL userinfo | deny | 不扩大 loopback trust boundary，也不携带凭据。 |
| `/api/*`、App/Core 资源或非 `/plugins/<id>/` path | deny | plugin 平面不可读取 Host endpoint 或任意 app assets。 |
| 未登记 plugin ID | deny | 动态 package name 不能自动获得资源能力。 |
| percent-encoded `.`、`/` 或 `\` 路径片段 | deny | URL decode 前即阻断遍历/重解释。 |

策略 origin 必须是精确 `http://127.0.0.1:<nonzero-port>/`，无 path/query/fragment/userinfo；plugin ID 限制为 ASCII `[A-Za-z0-9._-]`。`pluginRootURL` 亦只为已登记 ID 生成根路径，防止将 URL 构造当作 capability grant。

## 2. 受控 ModuleLoader boot graph admission

锁定官方 `parseBootManifest` 把 `window.__DSH_BOOT__` 拆为 module 与 plugin 两种视图，并要求每个 row 带 string `id`、`url`、`rev`；`external` 是异步 arrival 前必须满足的 module graph edge。[1] `GhostPlaneModuleManifest` 在 WebKit 看到 boot graph 前重建这个安全相关的 admission 子集：graph revision、entry ID/revision、同源资源 route、精确 `client.js?rev=<entry.rev>` URL、external/inject specifier 格式和 dependency-before-consumer 顺序。

它只接受已由 `GhostPlaneLoopbackPolicy` 登记的 plugin ID；bundle URL 所带 plugin directory 必须与 entry ID 严格相同。`external` 仅可指向图中先出现的 module（`/client` 后缀按官方规则归一）或调用方显式提供的 static seed specifier。缺失模块、反向依赖、重复 ID、错误 revision/query、外站/非 HTTP resource 或 plugin ID mismatch 一律在 factory load 前 typed reject。该对象**不**包含 factory closure、不会 materialize module，也不会模拟 JS loader；它只是硬 injection gate 的纯资料审查前半段。

## 3. 后续接入边界

GP-2 后续的独立 Plugin target 才可创建 `WKWebView`。它必须将每一次 main-frame 与 subresource `WKNavigationAction` / `WKNavigationResponse` 交给本 policy；拒绝必须在任何 bridge/module injection 之前发生。加载 native 生成的空 skeleton 可使用受控 base origin，但 SlotRegistry activation、可信 bootstrap module 和 hard injection gate 的最终 WebKit 生命周期仍需要另外实现。

> 本子阶段不宣称实现 WebKit sandbox、CSP、ModuleLoader、SlotRegistry、tapIndex sanitization、网络 response validation 或权限 bridge；这些均是 GP-2/T11.5 后续验收，不能由本 policy 的通过替代。

## 4. 登记制 WebKit target

`GlassPluginPlane` 是新增且唯一可承载 WebKit 的 SwiftPM library target。它依赖 `GlassCore` 与 `GlassSpec`，但 `GlassCore`、`GlassUI`、`GlassSnapshot` 和 `DeepSeekHarnessGlassApp` 的精确 resolved target dependencies 不包含它；`check-package-target-graph.py` 通过 `swift package describe --type json` 验证这一方向，且其自测以非法 App→PluginPlane edge 证明会失败，而非扫描 Swift import 文本。

`GhostPlaneWebViewHost` 只存在于该 target：它创建单一 `WKWebView`、使用 `WKWebsiteDataStore.nonPersistent()`、关闭 window opening，并把 main-frame 与 response URL 都送入 `GhostPlaneLoopbackPolicy`。policy 只额外允许精确 origin 根页作为 native content-empty skeleton document；所有其余允许路径仍须是已登记 plugin resource。`GlassPluginPlaneTests` 在 macOS 上验证真实 `WKWebView`、ephemeral store 与 policy boundary。Core/UI/App 的现有 NSView tree negative test 保持验证红区内无 WebView。

## 5. 验证资产

`GhostPlaneLoopbackPolicyTests` 覆盖同源已登记 plugin 放行、唯一 skeleton root、plugin root 构造、external/file/https/userinfo/port/path/unknown plugin/encoded traversal 负例及非 canonical origin 构造失败。`GhostPlaneModuleManifestTests` 覆盖已登记且拓扑有序的 graph 正例，以及 malformed graph、空/错 revision、重复 ID、resource mismatch、外站、未知 external 与 dependency-after-consumer 负例。两个 production source 都有对应 Linux Swift 6.2.4 可移植回归，且已接入 `portable-checks`。

## References

[1]: https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/modules/src/client/system.ts "Official ClientModuleSystem loader registration contract"

## 6. 官方动态运行时身份（为 T11.4/T11.5 保留）

锁定官方 `cordis-client-runner` 将每个 browser half 以 `pluginId`、不可变 `packageId`、精确 `pluginRunId`、`agentId` 和 `name` 表示；页面 live state 以 `pluginId` 收敛，重复同 run 为 no-op，另一 run 替换，unload 会移除 loader entry、失效 module factory 并清理 styles。[2] 官方动态 package 通过 `dyn/<pluginId>` 取得 module/loader entry identity，runner 只有在模块表、SlotRegistry、loader 和受 guard 的 host invocation 都可用时才 activation；`inject` 未满足时是成功但 parked 的 `waitingFor` 状态而不是静默失败。[2]

后续 T11.4 的诊断模型必须保留上述 plugin/package/run 三重身份以及 `active`、`waitingFor`、`evaluate`/`module-import`/`activate` failure 原因；不得仅以 package display name 或历史数组判断当前运行轨。当前 `GhostPlaneModuleManifest` 仅验证 boot graph，不模拟 Cordis fiber/SlotRegistry lifecycle。

[2]: https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/extensions/cordis-client-runner/src/client/runtime.ts "Official dynamic Cordis browser lifecycle"

## 7. 受控 `tapIndex` 重放计划

锁定官方 `WebServer` 先渲染结构化 index injections，随后按注册顺序把任意 `tapIndex((html) => html)` 回调作用到原始 HTML。[3] 该 callback 面在 Node/官方网页可执行任意字符串重写，**不能**原样跨越到 Ghost Plane：若把回调源码、HTML fragment、selector 或事件属性交给 WebKit，便会绕过 native skeleton、manifest admission 和 Plugin target 的唯一加载入口。

`GhostPlaneTapIndexReplay` 因而不是一般 HTML sanitizer，而是一个刻意狭窄的 host-side 兼容语言。每项记录都携带 `(pluginID, revision)`，并且只在已 admitted `GhostPlaneModuleManifest` 中存在相同 plugin ID 与精确 bundle revision 时生效。相同 target/mutation 的重复写入 fail-closed，避免把效果交给偶然的注册顺序；输出为 JSON-compatible primitive payload，未来 WebKit 只能通过参数化 `callAsyncJavaScript` 传入，而不得以字符串插值生成脚本。

| 允许 mutation | target | 约束 |
|---|---|---|
| `setCustomProperty` | 8 个原生固定 skeleton element ID | property 必须是 `--dsh-*` 或 `--ghost-*`；值限受控字符集，并拒绝 `url`、`expression`、`@import`。 |
| `setDataAttribute` | 同上 | attribute 必须是 `data-ghost-*`，值仅限 ASCII token。 |
| `addCompatibilityClass` | 同上 | class 必须是 `ghost-compat-*`。 |

该表故意不含 HTML、CSS selector、URL、事件 handler、style declaration、script source 或任意 bridge 名称。`GhostPlaneTapIndexReplayTests` 与 `glass/ci/ghost-plane-tap-index-replay-portable-check.swift` 覆盖图身份、revision、重复冲突、可执行 CSS URL、未限定 attribute 与 plugin class 负例；后者在 Linux Swift 6.2.4 通过并接入 `portable-checks`。

`GhostPlaneWebViewHost` 现以 `WKUserScript` 在 main-frame document start 安装固定、不可重写的 `window.__DSH_GHOST_PLANE__.applyTapIndex` renderer。host 只在 native skeleton 的最终 URL 经 policy 确认为 exact root 后允许写入；未完成、失败或重定向文档均为 `skeletonNotReady`。host 通过 `callAsyncJavaScript(arguments:)` 传递 `rendererPayload()`，不插值 record 内容；document 端再次验证 target ID、mutation kind、prefix、字符集与禁止 CSS 关键字。这给 runtime application 加上第二个独立的拒绝层，同时不增加任何 loader/bridge/module execution 能力。`GhostPlaneWebViewHostTests` 在 macOS target 验证未就绪拒绝、实际 DOM token/data/class 写入和无 executable attribute。

> 此阶段只完成受控 replay 的 Core admission 与 skeleton-only 参数化 WebKit application；没有宣称 WebKit 已提供官方 ModuleLoader、SlotRegistry 或 typed injection services。

[3]: https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/host/webserver/src/index.ts "Official WebServer index injection and tap order"

## 8. `__ModuleLoader__` queue facade

官方 `ClientModuleSystem` 以 `window.__ModuleLoader__` 的 queue-form facade 作为 bundle factory 先到达时的暂存入口；系统 boot 后才将该 facade 切换为 live registration，并在 factory 缺失、重复或 dependency unresolved 时显式失败。[1] `GhostPlaneWebViewHost` 因而在 main-frame document start 唯一创建不可重写的 queue facade：`load(registration)` 只接受 ASCII package/client ID 与 function factory，正常化 `/client` 后暂存 immutable record，并拒绝无效 registration。

该 facade 是 module table 的**唯一入口**，而不是完整 module system：当前没有 bundle arrival、live mode switch、static seed exports、factory materialization、`require`、Cordis Loader、SlotRegistry 或 typed injection activation。`GhostPlaneWebViewHostTests` 检查 facade 与 skeleton renderer 位于同一 document 且已具 queue surface；未来 T11.5 必须将已 admitted boot graph 与 static bridge services 接入这些后续阶段，才能声称 plugin client entry 激活。


## 9. 官方 queue/create/live facade 契约（2026-08-21 复核）

锁定官方 `packages/client/modules/src/index.ts:231-272` 的 `bootInjections(graph)` 安装顺序为：inline queue facade、modules/runtime parser-preload classic scripts、`__DSH_BOOT__` graph global。官方 `create(options)` 只允许在 `mode === "queue"` 调用；它定位预加载 `@deepseek-ai/dsh-client-modules` registration、从 pending queue 移除该项、以拒绝所有 early external 的 `require` materialize bootstrap factory，并确认 exports 同时提供 `createClientModuleSystem` 与 `apply`，随后才委托创建 live module system。

Ghost Plane 不能把上游 JS queue surface 自身当作执行授权。未来 queue→live/materialization 实现仍必须先经过 native admitted graph 的精确 `(pluginID, revision)` arrival、non-static dependency、activation permit 与 typed injection gates；任何 plugin page-global 自证、未经 host 观察的 factory 或 service object 都不得获准执行。

来源：锁定官方提交 `528c682e061696f5a160f363f236ecbf53cbd006`，`packages/client/modules/src/index.ts:231-272`。
