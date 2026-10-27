# Contributing

感谢关注 **量化终端（StockTerminal）**。欢迎 Issue / PR。

## 开发环境

- macOS 15+
- Xcode 16+ / Swift 6.0
- 可选：`gh`、本机已装好的 Swift 工具链

```bash
git clone https://github.com/skysh3n/StockTerminal.git
cd StockTerminal
swift test
swift run StockTerminal
# 或
./Scripts/build-app.sh && open /Applications/量化终端.app
```

## 约定

- **TradingCore** 禁止依赖 SwiftUI / AppKit；行情与撮合逻辑放这里。
- UI 改动后按项目习惯：能跑通则 `./Scripts/build-app.sh` 安装到 `/Applications/量化终端.app` 自测。
- 不要提交 `.env`、密钥、`.build/`、`build/`、`tokens.json`、个人 IDE 配置。
- PR 说明「改了什么 / 为什么」；行为变更尽量附截图或复现步骤。

## 语言

Issue / PR 中英均可；面向用户的文案优先中文。
