# RC8 Deliverables light：官方侧捕获记录

> **状态：official-only evidence。** 本记录固定 `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534` 的真实WebUI表面；它不构成原生视觉验收，也不允许勾选T6.
> 6。
> 

| 项目 | 锁定值 |
|---|---|
| 场景 | `deliverables-light` |
| 浏览器与来源 | Playwright Chromium，经锁定 `apps/web` scaffold |
| 视口 / DPR | 780 × 900 / 1 |
| Locale / 主题 | `en-US` / light |
| Host状态 | 新鲜隔离scaffold，RC8 `produced-files.overlay.yml`，十个成功 `write` tool result 的已结算turn，Host `canOpenPath=true` |
| 导航顺序 | 先在1280px选择seeded session，再缩至780px，避免窄rail按官方契约卸载tree descendants |
| 输出 | `deliverables-light-official.png`、`deliverables-light-official.json` |
| PNG SHA-256 | `67f24de6aa6b1143068b133cd344bd82df8d16f50333db6a6c2b18914777f3be` |
| ARIA JSON SHA-256 | `6c293f5b8791a440c7f700d81f705169b24b9dac8e34d485c58ff0e7df5ba533` |

官方侧运行了锁定上游 [`produced-files.
e2e.ts`][1] 的同一十写入事件语义；项目capture harness仅负责将这一已结算真实session扩展为可归档的PNG与body ARIA元数据。`vitest`场景通过，且metadata中`consoleWarnings`和`pageErrors`均为空。

| 人工视觉复核 | 观察结论 |
|---|---|
| 窄视口框架 | 780px时保留官方已展开sidebar（会话选择先在宽viewport完成，随后保持用户的narrow-expanded偏好）；仅conversation lane被压缩。 |
| tool到turn-tail顺序 | 十个`Write · path`行位于closing assistant prose之前；turn tail随后显示。 |
| Measured lane | `Produced`同一首行仅显示`关于我.md`和`index.html`两个basename chip，并显示精确`+ 8 files`。 |
| Folder action | `Show in folder`在同一grid第二行、chip lane起始列，ARIA为同名button；它依赖记录的loopback `canOpenPath=true`状态。 |
| 可访问性 | ARIA记录有`Open 关于我.md`、`Open index.html`、`Show in folder`；完整路径作为open label参数而不是只暴露basename。 |

下一步必须从当前SHA的macOS-26工件下载同视口原生`deliverables-light.
png`、comparison PNG及report JSON，再按`visual-validation-policy.json`将差异逐项分类。此场景当前仍为`report-only`。

## 复现命令

```bash
cd /home/ubuntu/reference/deepseek-harness-rc8-analysis
DSH_REFERENCE_SCREENSHOT_DIR=/tmp/official-deliverables-capture \
  corepack pnpm exec vitest run --config vitest.web.config.ts \
  apps/web/tests/capture-official-welcome.e2e.ts \
  -t 'captures official narrow Deliverables'
```

## References

[1]: https://github.
com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/apps/web/tests/produced-files.
e2e.ts "RC8 produced-files end-to-end scenario"
[2]: https://github.
com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/ui-deliverables/src/client/ProducedFiles.
tsx "RC8 ProducedFiles renderer"
[3]: https://github.
com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/ui-deliverables/src/client/ProducedFiles.
module.css "RC8 ProducedFiles layout"
