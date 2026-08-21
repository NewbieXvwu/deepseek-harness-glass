# 官方参考环境与视觉证据记录

本文件记录 DeepSeek Harness Glass 迁移所依赖的**外部、可复核事实**。它不替代 [TODO.md](../TODO.md) 的任务状态；TODO 仍是唯一允许勾选工作项的入口。

## 锁定官方来源

| 项目 | 已核验事实 | 来源 |
|---|---|---|
| 官方仓库 | `deepseek-ai/deepseek-harness` | [官方 GitHub 仓库](https://github.com/deepseek-ai/deepseek-harness) |
| 锁定源码 | `528c682e061696f5a160f363f236ecbf53cbd006`，官方 tag `dsh-v0.1.1-rc.1` | [锁定 commit](https://github.com/deepseek-ai/deepseek-harness/tree/528c682e061696f5a160f363f236ecbf53cbd006) |
| 包版本 | 锁定源码根 `package.json` 与 `apps/web/package.json` 均为 `0.1.1-rc.1` | [Web frontend package](https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/apps/web/package.json) |
| 官方三栏规格 | sidebar 默认 280、范围 264–420、rail 56、breakpoint 1024、中心最小 640、details 默认 360、范围 300–520；让步顺序为先压缩 details、再关闭 details、最后让中心列吸收不足。 | [官方 `columns.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/ui-layout/src/client/columns.ts) |
| Host wire contract | HTTP POST 的 `rpcId` 必须由 response 回显；SSE 承载 Host initiated request；业务错误属于 RPC result branch。 | [官方 API proxy README](https://github.com/deepseek-ai/deepseek-harness/blob/528c682e061696f5a160f363f236ecbf53cbd006/packages/host/apiproxy/README.md) |
| 原生材质边界 | Apple 建议优先使用标准 SwiftUI/AppKit 导航、split view、toolbar、sheet、popover 与控制；自定义 Liquid Glass 应节制，并测试透明度、对比度和动态效果偏好。 | [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) |

## 本地官方参考环境

官方仓库已克隆至 `/home/ubuntu/reference/deepseek-harness` 并检出上述 commit。项目所需 Node 版本为 `24.19.0`，参考环境以该本地运行时执行 `pnpm install --frozen-lockfile`。`apps/web` 的真实 Vite 产物已从锁定源码构建，并使用官方 `apps/web/tests/scaffold.ts` 的真实 Host composition、隔离 `DSH_HOME` 和 keyless fixture 启动。

官方 Playwright 依赖必须通过 **Web frontend package 自身**的命令安装，原因是根工具版本与 `apps/web` 解析到的 Playwright 浏览器 revision 不一定相同。已验证的命令是：

```bash
corepack pnpm --filter @deepseek-ai/dsh-web-frontend exec playwright install chromium
```

## 当前已验证截图对照

GitHub Actions `native-ui` [run 32155838142](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32155838142) 对提交 `c77621a1ded2c339a9efa28cc6c9029331d4869a` 成功。它在 `macos-26` 完成以下外部事实验证：从锁定官方源码构建 WebUI、以 Playwright 捕获官方 `welcome-no-workspace-light`、构建原生 App、捕获原生欢迎态，并生成量化差异工件。

| 场景 | 配对条件 | 结果 |
|---|---|---|
| `welcome-no-workspace-light` | 1280×840、English、light、DPR 1、无 workspace、无 session | 官方截图、无障碍/几何 JSON、原生截图、放大差异图、三栏对照图与 JSON 报告均作为 Actions artifact 上传。 |

本次差异报告的量化值为：`exactChangedRatio = 0.30739118`、`materiallyChangedRatio = 0.02211961`、`meanAbsoluteChannelDifference = 2.629437`。这些数字**不是通过阈值**，而是证明当前实现仍存在必须按场景逐项分类与修复的可观察差异；详见版本化评审记录 [welcome-no-workspace-light.md](../visual-review/official-99f6f02/welcome-no-workspace-light.md)。

## 支持基线结论

官方 RC8 tag `dsh-v0.1.1-rc.1` 指向 `528c682e061696f5a160f363f236ecbf53cbd006`；锁定源码根包和 Web frontend 包均为 `0.1.1-rc.1`。根包声明的 Node 要求为 `^22.19.0 || >=24.0.0`，项目继续锁定 Node `24.19.0`。因此当前唯一支持基线为 **`dsh 0.1.1-rc.1`、`dsh-web-frontend 0.1.1-rc.1`、Node `24.19.0` 和 commit `528c682e`**。后续 Host 升级必须同时更新来源、DTO/fixture/spec、视觉证据和支持矩阵，不得单独移动其中任一版本。
