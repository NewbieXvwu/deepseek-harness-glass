# GP-5：PermissionBroker 首调授权

**状态：** 已实现纯 Core `GhostPlanePermissionBroker`、Core XCTest 与 Linux Swift 6.2.4 回归；原生授权对话框、TCC 路径、平台 API adapters、设置撤销界面和外链 URL confirmation 仍未接入，GP-5 保持未完成。

`GhostPlanePermissionBroker` 以 `(pluginID, capability)` 作为唯一决策键。notification、clipboard read/write、download、open file picker 和 external navigation 初始均为 `needsNativePrompt`；只有 native confirmation UI 可调用 `resolveFirstRequest` 记住 grant 或 deny。已记忆项不能被后续请求覆盖，Settings 只能 revoke，撤销后下一次调用再次 prompt，不能创建预授权 grant。非法 plugin identity 永远拒绝且不留下 record。

粘贴/拖拽图片不是此 broker 的 bytes 通道：未来 adapter 必须把 temporary file URL 传给已有 `NativeImageAttachmentAdmission`，让 ImageIO、MIME、dimensions、pixel 与 message limits 在 Host prompt 前检查。[1]

`GhostPlanePermissionBrokerTests` 和 `ghost-plane-permission-broker-portable-check.swift` 覆盖首调、grant/deny 记忆、不可覆盖、按 capability 隔离、revoke 及非法 ID；可移植回归已接入 `portable-checks`。

> 本阶段不声称插件已经能调用系统 Notification、NSPasteboard、NSSavePanel、NSOpenPanel、NWPathMonitor 或 OAuth 跳转；这些 API 只能在相应 native adapter 已经检查本 broker 的决策后实施。

## References

[1]: ../glass/Sources/Core/Session/NativeImageAttachmentAdmission.swift "Project native image admission boundary"
