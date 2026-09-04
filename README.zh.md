# DeepSeek Harness Glass

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的原生 macOS 客户端——你熟悉的 dsh，装进一扇真正的玻璃窗口。

本仓库 fork 自 [qniequn-boop/deepseek-harness-glass](https://github.
com/qniequn-boop/deepseek-harness-glass)。
上游项目用原生玻璃窗口包裹官方 WebUI；
本 fork 更进一步，用 Swift 6（SwiftUI + AppKit）完整重写浏览器客户端，官方 Host 继续担任后端。
macOS CI 会实际装载核心原生表面并递归检查其 `NSView` tree 中不存在 `WKWebView`，测试另含真实注入 WebView 的负例；
第三方插件以 Ghost Plane 运行时达成全兼容（一层透明共享 Web 平面承载官方模块表、槽位注册表与几何精确的骨架 DOM，未修改的插件 client 原样挂载到其预期锚点），原生 Manifest/Adapter 作为可选精品快车道，
详见 [docs/PLUGIN_COMPATIBILITY_PROPOSAL.


md](docs/PLUGIN_COMPATIBILITY_PROPOSAL.md)。

- **English:** [README.md](README.md)

## 现状

开发中。
已完成：应用外壳（窗口、菜单栏、与官方列算法一致的三栏布局）、带构建验证与诊断的 Host 生命周期、基于锁定官方版本录制 fixture 的强类型 RPC/SSE 传输层、会话状态（历史分页、投影存储、队列/任务）、工作区管理对话框、欢迎页，以及无障碍基线。
待完成：完整会话界面、工具详情、设置页面与插件支持。

任务级进度见 [TODO.md](TODO.md)，工作规则见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 基线

| 项目 | 固定值 |
|---|---|
| 官方源码 | [`deepseek-ai/deepseek-harness@a66e470`](https://github.
com/deepseek-ai/deepseek-harness/tree/a66e4702047846cdaa10c66c9d3df3951f5ea70d) |
| DSH 包 | `@deepseek-ai/dsh` / `@deepseek-ai/dsh-web-frontend` `0.1.2-rc.1` |
| 运行时 | 应用内置 Node `24.19.0` |
| 平台 | macOS 26+、Apple Silicon；构建需 Xcode 26+、Swift 6 |

应用启动时按 `glass/Sources/Spec/SupportedHostBuilds.json` 校验 Host 构建。未知构建会显示为未验证，在完成验证前保持只读。

## 工作方式

应用内置固定版本的 Node 运行时与锁定的 DSH 后端 payload，在本地回环地址上启动 `dsh web --port 0`，通过强类型 HTTP RPC 与 SSE 通信。会话、工作区、设置、凭据、模型等持久状态全部归 Host 所有，原生端负责渲染并回传用户操作。

可见文本、颜色、间距与列宽来自 `OfficialUISpec`——它从锁定官方源码生成（locale、主题 token、`columns.
ts` fixture、交互场景、RPC 契约），CI 会重新生成并比对以防漂移。Liquid Glass 用于导航与控制层，内容层使用系统材质。

```text
glass/
├── Sources/
│   ├── App/        生命周期、窗口、菜单栏
│   ├── Core/       Host 进程、传输层、会话状态、设置
│   ├── Spec/       生成的官方规格与 fixture
│   ├── UI/         原生 shell、侧栏、工作区、会话
│   └── Snapshot/   CI 快照导出器
└── Tests/          契约、reducer、快照、无障碍测试
```

## 视觉验证

每个已迁移的 UI 状态都要与同一 fixture、同一视口、DPR、语言和颜色模式下捕获的官方 WebUI 截图配对。
CI 在 `macos-26` 上构建应用、捕获原生快照、用 `glass/ci/compare_visual_pair.
py` 与官方截图比较，并把两组图片和量化报告作为 artifact 上传。
sidebar/inspector 的系统材质带通过 `--column-fixtures` 排除在像素比对之外，改做结构性验证；
场景在人工审阅实测数值后从 `report-only` 转为 `enforce`（阈值写在 `visual-validation-policy.json`）。

## 构建

前置条件：Xcode 26+ 命令行工具、npm，以及两次下载所需的网络。

```sh
# 1. 内置 Node 运行时（固定版本）
mkdir -p glass/build/node
curl -fsSL https://nodejs.org/dist/v24.19.0/node-v24.19.0-darwin-arm64.tar.gz -o /tmp/node.tgz
tar -xzf /tmp/node.tgz -C /tmp
cp /tmp/node-v24.19.0-darwin-arm64/bin/node glass/build/node/node

# 2. 后端 payload + 组装
cd glass
./repair-backend.sh        # 安装固定版本的 dsh payload 并做冒烟测试
./assemble.sh              # 编译、ad-hoc 签名、安装 .app
```

`assemble.
sh` 默认写入 `/Applications/DeepSeek Harness.
app`，可用 `APP_PATH` 覆盖。
权威构建配方是 CI 工作流 [`.
github/workflows/native-ui.
yml`](.github/workflows/native-ui.yml)，其中包含完整门禁：规格/locale/token/布局/契约检查、`swift build`、各 XCTest 套件、应用组装、快照捕获与官方/原生视觉比对。

修改面向官方的行为前，可先在本地跑：

```bash
python3 glass/ci/check-official-spec.py
python3 glass/ci/test-package-target-graph.py
```

## 许可证与归属

MIT，见 [LICENSE](LICENSE)；捆绑组件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。本项目是开源 DeepSeek Harness 的独立客户端，与 DeepSeek 无隶属或背书关系。
