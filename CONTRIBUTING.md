# Contributing to DeepSeek Harness Glass

本项目的目标是在固定的官方基线上复刻 DeepSeek Harness 的官方客户端 UI，并保证每一步都可以回归。所有任务以 [TODO.md](TODO.md) 为跨会话入口。

## 1. 开始前确认基线

```bash
git status --short
git log -10 --oneline
swift build --package-path glass
swift test --package-path glass
```

官方基线固定为 `deepseek-ai/deepseek-harness@a66e4702047846cdaa10c66c9d3df3951f5ea70d`（`dsh-v0.1.2-rc.1`）；
支持的 Host 记录在 `glass/Sources/Spec/SupportedHostBuilds.json`。一切以锁定源码为准。

## 2. 官方来源到实现的闭环

每个任务先登记来源，再写 Swift 代码：

| 记录项 | 内容 |
|---|---|
| 官方来源 | 固定 commit、源码文件、行号或 CSS selector、相关 locale key、token、图标 |
| Host/协议 | RPC method、请求/响应 DTO、SSE frame、错误、取消与 revision 语义 |
| UI 状态 | 初始 fixture、动作序列、窗口尺寸、DPR、语言、颜色模式、辅助功能条件与预期布局树 |
| 原生映射 | `OfficialUISpec` 键、Swift type/View/Reducer 文件、可访问性 label |

可见字符串来自受控官方 locale；颜色、间距、圆角、字体和图标经官方 token/资产映射取得。

## 3. 测试门禁

| 变更类别 | 必需证据 |
|---|---|
| 官方文本、图标、token、布局 | `OfficialUISpec` 来源映射、locale/token/layout 测试 |
| RPC/SSE/DTO | Codable round-trip、真实 Host 或经审计 fixture、`rpcId`、取消、错误、冲突和重连测试 |
| Reducer/事件 | 每次 raw event append 的 node snapshot、乱序/重复/replay/unknown event 安全处理 |
| 原生界面 | macOS 26 UI test、键盘路径、VoiceOver label、焦点 |
| Glass 或自定义控件 | `GlassPolicy` 理由、容器策略、Reduce Motion/Transparency、Increase Contrast、Light/Dark 测试 |

提交前运行适用的本地检查；推送后等待并审阅当前 SHA 的 GitHub Actions 结果。

测试必须真实断言。因环境缺失而静默通过的 skip、只检查输出里有没有“没问题”字样的断言，都不算证据——这类测试宁可删除，也不要留着制造绿色假象。

## 4. TODO 更新纪律

TODO 条目是原子完成单元：

1. 确认依赖的条目已完成。
2. 完成来源映射、实现、测试和证据。
3. 关联代码 SHA 的 macOS GitHub Actions 成功后，才把条目从 `- [ ]` 改为 `- [x]`。
4. 验收条件缺失时，把阻塞事实写进 TODO，保持未勾选。

提交信息包含任务编号和可观察结果，例如 `feat(T10.1): render native Settings Root from official spec`。

## 5. Host 升级与发布

Host payload 升级顺序：锁定新官方 commit → 生成和审阅 `OfficialUISpec` → 更新 DTO → reducer 回归 → 无障碍与性能 → 更新 `SupportedHostBuilds.json` → 当前 SHA CI 成功。

正式发布还需要 clean environment 构建、Build Manifest、Developer ID 签名、Hardened Runtime、公证和 stapling。

## 6. 变更提交流程（强制）

**禁止直接向 `main` 推送变更。** 所有变更必须走分支 → PR → CI 全绿 → 审阅 → 合并：

1. 从 `main` 切出功能分支：`git switch -c feat/TXX.x-<short-name>`。
2. 小步提交，一条提交一个主题。
3. 推送前自检（必须全部通过）：
   - `swift build --package-path glass`
   - `swift test --package-path glass`
   - `python3 tools/check-markdown-links.py`
4. 推送分支并开启 PR，按 `.github/pull_request_template.md` 填写自检清单。
5. 等待 `build` 工作流全绿；任何红色必须修复或提供 review 豁免的理由。
6. 审阅人复核后合并；合并使用 **Squash and merge**，保留单一主题化提交。

质量红线（违反即打回）：

- 无恒真/镜像/仪式断言（`XCTAssertTrue(静态常量)`、测试复制实现、只验元数据不验行为）。
- 无盲等时序（`Task.sleep` 代替 expectation/eventually）、无忙轮询死等、无 `string contains` 代替精确断言。
- 无纯预览假数据被当作业务测试。
- 无吞错测试（`catch { return false }` 不记录、空 catch）。
- 删除低价值测试比保留假绿测试更受欢迎。
