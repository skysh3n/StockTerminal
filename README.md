# 量化终端（StockTerminal）

Mac 原生「看盘 + 交易」专业终端。SwiftUI 原生开发。

- **行情：真实数据**（免密钥公开接口：腾讯行情快照/K线/五档 + 东方财富逐笔），
启动时自动探测，失败或离线时整体回退内置**模拟行情**
- **交易：本地模拟撮合**（真实行情驱动；接真实券商柜台需资质与专线，协议已预留）

## 运行

```bash
swift run StockTerminal          # 开发模式（裸可执行，自动进前台）
```

打包成正规 .app（中文名称 / Dock 图标 / ad-hoc 签名）：

```bash
./Scripts/build-app.sh && open /Applications/量化终端.app
```

用 Xcode 开发：打开 `StockTerminal.xcodeproj`，选「量化终端」scheme，⌘R 运行。
App 源码目录 `Sources/StockTerminalApp` 以同步文件夹接入（增删文件无需改工程），
`TradingCore` / `DesignSystem` 通过本地 Swift 包引用；同一 scheme 下 ⌘U 跑全部单测。

```bash
open StockTerminal.xcodeproj
```

测试（33 个：撮合/资金/T+1/指标/数据生成）：

```bash
swift test
```

导出跨平台设计 tokens（供 iOS / Windows / Linux 映射）：

```bash
swift run tokens-export > tokens.json
```

## 数据源说明

| 数据 | 来源 | 频率 |
|---|---|---|
| 全市场搜索（代码/名称） | 东财 `searchapi` | 防抖 250ms 按需 |
| 快照 + 买卖五档（批量） | 腾讯 `qt.gtimg.cn` | 盘中 3s / 休市 30s |
| 日K / 周K / 1分 / 5分 | 腾讯 `ifzq.gtimg.cn` | 盘中 5s 增量 |
| 分时（最近交易日分钟序列） | 同 1 分钟K | — |
| 逐笔成交 | 东方财富 `push2his` | 盘中 3s（休市日接口无数据） |

- 顶部徽章显示当前数据源；休市时显示「实时行情 · 休市」，行情为最近交易日收盘
- 真实行情模式下，模拟撮合引擎由真实报价驱动（`QuoteBridge`），持仓市值/挂单撮合/市价成交全部使用真实价格
- 离线/接口不可用时自动回退全 Mock（徽章显示「模拟数据」）

## 功能（雏形）

- 自选股列表：实时跳动、红涨绿跌、价格闪烁、右键删除
- **全市场搜索**：按代码/名称搜全 A 股（沪/深/北），回车或点击加入自选并即时订阅行情
- K 线图：蜡烛 + 成交量；捏合缩放时间轴、触控板两指左右平移看前后 K（上下两指不缩放）、传统鼠标滚轮仍可缩放、拖拽平移、悬停十字光标、双击复位；分时 / 1分 / 5分 / 日K / 周K（⌘1–⌘5）
- **技术指标库**（`TradingCore/Indicators`，纯函数、可移植）：
  - 主图叠加：MA5/10/20/60 · EMA · BOLL(20,2)
  - 副图：VOL · MACD(12,26,9) · KDJ(9,3,3) · RSI(6,12,24)
  - **支撑压力**：分形法识别摆动高低点，按价格聚类合并（±0.5%），相对现价分出近端 2 压力/2 支撑；触及次数越多线越粗并标注 ×N，主图可一键开关
- 五档盘口（深度条）+ 逐笔成交（内外盘着色）
- 交易闭环：限价/市价、整手与资金校验、A股费用、T+1、挂单撮合、撤单；持仓/委托/成交三表
- 账户资产：总资产 / 可用 / 市值 / 当日盈亏

## 架构（跨平台预留）

```
Sources/
├── TradingCore/          ★ 纯逻辑核心（零 UI 依赖）
│   ├── Models/           Codable+Sendable 模型
│   ├── Services/         三个服务协议 = 跨平台接口边界：
│   │                     MarketDataService / TradingService / AccountService
│   ├── Indicators/       技术指标库（SMA/EMA/MACD/KDJ/RSI/BOLL + 指标图元）
│   ├── Simulation/       模拟撮合：MatchingEngine、费用、EventHubs、QuoteBridge
│   ├── MarketData/       行情源。Mock 与腾讯/东财互不依赖撮合实现细节
│   │   ├── Mock/         随机游走、分形 K 线、时钟、假股票池
│   │   ├── Tencent/
│   │   └── Eastmoney/
│   └── Platform/         平台相关编解码（GB18030），不散落在行情客户端里
├── DesignSystem/         ★ 平台无关 design tokens（DesignSpec → tokens.json）
└── StockTerminalApp/     macOS SwiftUI 应用层
    ├── Theme/            tokens → SwiftUI 绑定；Sem = 涨跌配色唯一入口
    ├── Stores/           @MainActor @Observable stores；AppEnvironment = 组合根
    └── Views/            三栏终端布局；探测完成（isReady）后才挂上面板
```

**换平台的契约**：iOS 用 SwiftUI 复用协议形态与 stores 逻辑；Windows/Linux 读
`tokens.json` 还原设计语言，按同一协议实现原生 UI。指标库为纯函数，可逐行移植。

## 性能设计

- 每标的独立 `@Observable SymbolState`：细粒度失效
- K 线增量合并（只更新尾 bar，MA 只算尾部窗口）
- 图表三层分离：光标独立层；蜡烛批量 Path 绘制
- 无持续隐式动画（闪烁为瞬时点亮）
- 数据驱动：休市/无更新时 UI 零开销（实测真实数据休市态 CPU ≈ 0.4%）

## 路线图

- [ ] 接入真实券商柜台（交易协议已预留）
- [ ] iOS 版
- [ ] 画线工具、多指标同屏、条件预警
- [ ] Windows / Linux 原生 UI
