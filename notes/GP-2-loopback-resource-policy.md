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

## 4. 验证资产

`GhostPlaneLoopbackPolicyTests` 覆盖同源已登记 plugin 放行、plugin root 构造、external/file/https/userinfo/port/path/unknown plugin/encoded traversal 负例及非 canonical origin 构造失败。`GhostPlaneModuleManifestTests` 覆盖已登记且拓扑有序的 graph 正例，以及 malformed graph、空/错 revision、重复 ID、resource mismatch、外站、未知 external 与 dependency-after-consumer 负例。两个 production source 都有对应 Linux Swift 6.2.4 可移植回归，且已接入 `portable-checks`。

## References

[1]: https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/modules/src/client/system.ts "Official ClientModuleSystem loader registration contract"
