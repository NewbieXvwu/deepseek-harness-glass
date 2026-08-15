# DeepSeek Harness Glass

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的原生 macOS 外壳——
**你熟悉的 dsh，装进一块真正的液态玻璃里。**

DeepSeek Harness Glass 把官方 `dsh` 引擎和它的 Web 界面封装成一个自包含的
macOS 应用。外壳不是 Electron / Tauri，而是一个精简的 SwiftUI 程序：整个窗口
直接落在苹果公开的
[`glassEffect`](https://developer.apple.com/documentation/swiftui/glasseffect(_:in:))
材质上，边缘折射、透镜感和分层材质由系统渲染，与 macOS 26 原生应用一致，
而非 CSS 模拟。

- **英文 README:** [README.md](README.md)

## 系统要求

- macOS 26 或更高（液态玻璃是 Tahoe 时代的 API）
- Apple 芯片（arm64）

## 安装

从 [Releases](https://github.com/qniequn-boop/deepseek-harness-glass/releases)
下载 `DeepSeek Harness Glass-<版本>.dmg`，打开后把应用拖进「应用程序」。

当前构建为 ad-hoc 签名、未公证。首次打开时 macOS 会提示「无法验证开发者」：
**右键点击应用 → 打开**，再确认一次即可（仅需一次）。

首次运行后在应用内的「设置」中填入你自己的 DeepSeek API Key。应用数据存放于
`~/.dsh`——与 dsh 命令行版共用同一目录，已有的会话、profile 和
`cordis.patch.yml` 补丁会自动生效。

## 特性

- **真·液态玻璃** — 窗口背景是原生 `glassEffect` 材质，边缘光学、圆角处理、
  折射全部由系统渲染，与 macOS 26 自带应用同款。
- **全窗玻璃** — 玻璃延伸到标题栏区域（`fullSizeContentView` + 零安全区宿主
  视图），顶部没有"无玻璃"的条带。
- **完全自包含** — 内置 Node.js v24 与完整 dsh 后端 payload
  （`@deepseek-ai/dsh`、`@deepseek-ai/dsh-web-frontend`，精确 pin 版本）。
  无需安装 Node.js，运行时不下载任何东西。
- **与 CLI 共享状态** — `DSH_HOME` 默认 `~/.dsh`：凭据、会话、设置、已安装
  插件与命令行版完全一致；可用 `DSH_HOME` 环境变量覆盖。
- **动态文字对比度** — 外壳在启动与更换壁纸时采样桌面壁纸平均亮度，在深/浅
  两套文字色板间带迟滞地切换；拖动窗口绝不触发翻转（苹果的设计原则：大表面
  不应随背景翻转）。
- **层级磨砂** — 输入框、弹窗、菜单、悬浮卡各有递进半透明着色与
  `backdrop-filter` 扫描，悬浮面呈现"玻璃叠玻璃"的层次。
- **干净的生命周期** — 退出、关窗或被 kill 都会先终止内置后端，不留孤儿进程。

## 工作原理

```
DeepSeek Harness.app
└── Contents/
    ├── MacOS/DeepSeek Harness        ← Swift 外壳（glass/Sources/main.swift）
    └── Resources/
        ├── node/node                 ← 内置 Node.js v24（官方二进制）
        └── backend/node_modules/     ← 精确 pin 的 dsh 引擎 + Web 前端
```

1. 外壳用内置 Node 启动后端：
   `node --expose-internals …/@deepseek-ai/dsh/lib/bin.js web --port 0`
   （`--expose-internals` 是 dsh web profile 中 HMR 服务的要求）。
2. 解析 stdout 里的 `dsh web: http://127.0.0.1:<端口>`，用透明 `WKWebView`
   加载。端口随机、只绑回环地址，不对外暴露。
3. `WKUserScript` 注入 `GLASS_CSS`，重染 dsh 的设计令牌（`--dsw-alias-*`，
   前端自带的主题扩展点），整界面半透明化，dsh 源码零改动。
4. 原生玻璃材质位于透明网页内容之下。

## 从源码构建

前置条件：Xcode 命令行工具（`swiftc`）、`npm`、网络连接（下载下面两项）。

```sh
# 1. 内置 Node 运行时（官方二进制，精确 pin）
mkdir -p glass/build/node
curl -fsSL https://nodejs.org/dist/v24.19.0/node-v24.19.0-darwin-arm64.tar.gz -o /tmp/node.tgz
tar -xzf /tmp/node.tgz -C /tmp
cp /tmp/node-v24.19.0-darwin-arm64/bin/node glass/build/node/node

# 2. 后端 payload（npm 精确 pin）+ 冒烟测试 + 组装
cd glass
./repair-backend.sh
```

应用默认输出到 `/Applications/DeepSeek Harness.app`；用 `APP_PATH` 指定别处：

```sh
APP_PATH="$PWD/dist/DeepSeek Harness.app" ./assemble.sh
```

制作安装镜像：

```sh
mkdir -p dmg-stage && cp -R "/Applications/DeepSeek Harness.app" dmg-stage/
ln -s /Applications dmg-stage/Applications
hdiutil create -volname "DeepSeek Harness Glass" -srcfolder dmg-stage \
  -ov -format UDZO "dist/DeepSeek Harness Glass-0.3.0.dmg"
```

推送 `v*` 标签会触发 `.github/workflows/release.yml`，自动完成以上全部步骤
并把 DMG 挂到 Release。

## 故障排查

**「DeepSeek Harness 启动失败（code 1）」** — 内置后端 payload 缺包。运行：

```sh
cd glass && ./repair-backend.sh
```

该脚本会以精确 pin 重装 payload、冒烟测试后端并重新打包。

**App 与 CLI 不能同时运行** — 两者共用 `~/.dsh`。需要同时运行时给 App 设置
不同的 `DSH_HOME`。

## 项目结构

```
glass/
  Sources/main.swift     全部外壳逻辑（约 700 行，唯一自定义代码）
  assemble.sh            构建 + ad-hoc 签名 + 原子替换
  repair-backend.sh      一键重装 payload + 冒烟测试 + 重新打包
  Info.plist             bundle 元数据（LSMinimumSystemVersion 26.0）
build/icon.icns          应用图标（源自 dsh 鲸鱼 favicon）
```

## 设计说明

窗口 `isOpaque = false`、背景透明，玻璃材质才能折射桌面。网页内容出于平台
隐私边界无法采样窗口背后的画面，因此悬浮面采用分层着色 + 对页面自身内容做
`backdrop-filter`，而非第二道原生模糊。文字令牌保持纯色，配合 0.5% 白色衬底
与抗锯齿渲染，避免背景色渗入字形。

## 免责声明

本项目是开源 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
的独立、非官方外壳，与 DeepSeek 无隶属或背书关系。「DeepSeek」及相关标识归
其权利人所有。

## 许可证

MIT — 见 [LICENSE](LICENSE)。捆绑组件的许可见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
