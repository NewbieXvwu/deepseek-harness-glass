# DeepSeek Harness RC8 上游调研记录

本记录用于 RC8 升级任务的来源追溯；实现前需以锁定 tag 的源码差异为准。

| 项目 | 已核验结论 | 来源 |
| --- | --- | --- |
| 官方仓库 | 上游为 `deepseek-ai/deepseek-harness`。 | [官方 GitHub 仓库](https://github.com/deepseek-ai/deepseek-harness) |
| RC8 tag | 官方 tag 为 `dsh-v0.1.0-rc.8`。 | [RC8 tag](https://github.com/deepseek-ai/deepseek-harness/tree/dsh-v0.1.0-rc.8) |
| RC8 提交 | tag 页面标示提交短 SHA 为 `141eb6f`；本地仅抓取 tag 后使用完整 SHA 写入受控规格。 | [RC8 tag](https://github.com/deepseek-ai/deepseek-harness/tree/dsh-v0.
1.0-rc.
8) |
| 软件包版本 | RC8 根包及 `@deepseek-ai/dsh-web-frontend` 的版本均为 `0.1.0-rc.8`。 | [RC8 根 package.json](https://github.
com/deepseek-ai/deepseek-harness/blob/dsh-v0.1.0-rc.8/package.json) [RC8 Web package.
json](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.1.0-rc.8/apps/web/package.json) |
| 初步影响面 | 官方 `packages/host/apiproxy`、`apps/web` 和多处 `packages/client/ui-*` 在 RC7→RC8 间均有改动；具体实现以本地 tag diff 与审计 fixture 为准。
| [RC8 源码树](https://github.com/deepseek-ai/deepseek-harness/tree/dsh-v0.1.
0-rc.8) |

> 该记录不代表 RC8 适配已完成，也不用于勾选 `TODO.md`。协议、文案、token、布局与可访问性仍须分别落实为受控规格、Swift 实现和回归测试。

## 本地检索环境

官方 RC7/RC8 tag 的只读分析副本位于 `/home/ubuntu/reference/deepseek-harness-rc8-analysis`。其中不执行上游代码，只用于 `git diff`、源码检索与 fixture/spec 抽取。

## 参考链接

[1] [DeepSeek Harness 官方仓库](https://github.com/deepseek-ai/deepseek-harness)

[2] [DeepSeek Harness `dsh-v0.1.0-rc.8` tag](https://github.com/deepseek-ai/deepseek-harness/tree/dsh-v0.1.0-rc.8)

## RC7→RC8 已确认的兼容性变更

| 领域 | RC8 官方源码变更 | 本项目适配决策 | 官方来源 |
| --- | --- | --- | --- |
| Host 描述 | `host.describe` 成功值新增必填 `home: string`，由 Host `homedir()` 提供。 | `HostDescribeResponse` 解码 `home`，壳层仅在已验证端点上读取并将该值注入界面。 | [host.
schema.ts](https://github.
com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/host/apiproxy/src/api/host.schema.ts) [api-proxy.
ts](https://github.
com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/host/apiproxy/src/api-proxy.ts) |
| 路径显示 | 官方 `abbreviateHomePath` 只将 POSIX 的 home 与其后代显示为 `~`/`~/…`；Windows 驱动器和 UNC 路径保持原样，根目录不缩写。工作区悬停路径与工具路径会消费这一 Host 字段。
| 新增 `HostPathDisplay` 并在工作区行的原生 hover help 中使用，完整 Host 路径不变。 | [path.
ts](https://github.
com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/runtime/src/client/workspaces/path.
ts) [WorkspaceBrowser.tsx](https://github.
com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/ui-workspace/src/client/WorkspaceBrowser.
tsx) |
| 图像投影 | `SessionProjectionMap.imageLimits` 由 attachment 服务提供；字段包含每张大小、每消息数量、总大小、像素、最大边长和媒体类型。投影不存在意味着该服务未组合，客户端不应凭空设定限制。
| 新增 `ImageAttachmentLimits` 并在 `NativeSessionStore` 以只读、类型化方式读取 `imageLimits`。 | [sessions.ts](https://github.
com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/host/apiproxy/src/api/sessions.ts) [sessions.schema.
ts](https://github.
com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/host/apiproxy/src/api/sessions.schema.ts) |

## 运行时元数据

RC8 根包声明 `packageManager: pnpm@11.7.0` 和 Node 兼容范围 `^22.19.0 || >=24.0.0`；项目锁定的 Node `24.19.0` 满足该范围。[3]

[3] [RC8 根 package.json](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/package.json)

## 视觉证据状态

此前的 `official-99f6f02` 视觉审查与截图仅是 RC7 历史记录。
RC8 的 UI 来源和交互场景已重新绑定；当前分支必须由 macOS-26 CI 重新生成 RC8 官方/原生配对图、DOM/ARIA/几何 JSON、差异报告与人工分类，才可获得新的视觉验收证据。

