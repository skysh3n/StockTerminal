import Foundation
import Observation
import TradingCore

/// 依赖注入容器与组合根。探测完成前不创建 store，界面只在 `isReady` 之后挂上。
///
/// - 探测到真实行情（腾讯快照/K 线 + 东财逐笔）→ 真实行情 + `QuoteBridge` 驱动的模拟撮合
/// - 探测失败或离线 → 内置模拟行情（含模拟时钟）
/// 交易始终走模拟撮合。接真实券商柜台需要资质与专线，协议已预留。
@MainActor
@Observable
final class AppEnvironment {
    private var marketService: (any MarketDataService)?
    private var tradingService: (any TradingService)?
    private var accountService: (any AccountService)?

    private var marketStore: MarketStore?
    private var watchlistStore: WatchlistStore?
    private var tradingStore: TradingStore?
    private var portfolioStore: PortfolioStore?

    private var quoteBridge: QuoteBridge?

    private(set) var isReady = false
    private(set) var usingRealMarket = false

    /// 仅在 `isReady` 之后由界面读取。
    var market: MarketStore { marketStore! }
    var watchlist: WatchlistStore { watchlistStore! }
    var trading: TradingStore { tradingStore! }
    var portfolio: PortfolioStore { portfolioStore! }

    static func live() -> AppEnvironment { AppEnvironment() }

    /// 探测数据源，创建唯一一套服务和 store，再建立订阅。
    func bootstrap() async {
        guard !isReady else { return }

        let universe = MockSymbolUniverse.symbols
        let defaultWatchlist = MockSymbolUniverse.defaultWatchlist
        let initialCash = Decimal(1_000_000)

        let marketSvc: any MarketDataService
        let tradingSvc: any TradingService
        let accountSvc: any AccountService

        if let probeSymbol = universe.first,
           await RealMarketDataService.probe(symbol: probeSymbol) {
            let hubs = EventHubs()
            let engine = MatchingEngine(symbols: universe, hubs: hubs, initialCash: initialCash)
            let realMarket = RealMarketDataService(universe: universe)
            let bridge = QuoteBridge(engine: engine, market: realMarket, symbols: universe)
            bridge.start()
            quoteBridge = bridge
            marketSvc = realMarket
            tradingSvc = MockTradingService(engine: engine, hubs: hubs)
            accountSvc = MockAccountService(engine: engine, hubs: hubs)
            usingRealMarket = true
        } else {
            let mock = MockFactory.make(initialCash: initialCash, startClock: true)
            marketSvc = mock.market
            tradingSvc = mock.trading
            accountSvc = mock.account
            usingRealMarket = false
        }

        let watchlist = WatchlistStore(universe: universe, defaultWatchlist: defaultWatchlist)
        let market = MarketStore(marketSvc)
        let trading = TradingStore(tradingSvc)
        let portfolio = PortfolioStore(accountSvc)

        var symbols = (try? await marketSvc.universe()) ?? universe
        let known = Set(symbols.map(\.fullCode))
        for code in watchlist.codes where !known.contains(code) {
            if let sym = watchlist.symbol(for: code) { symbols.append(sym) }
        }
        await market.start(symbols: symbols)
        await trading.start()
        await portfolio.start()

        if let code = watchlist.selectedCode, let sym = watchlist.symbol(for: code) {
            let ref = market.state(for: code)?.quote?.lastPrice
            trading.draft.setSymbol(code: code, name: sym.name, refPrice: ref)
            await market.select(symbol: sym, timeFrame: watchlist.selectedTimeFrame)
        }

        marketService = marketSvc
        tradingService = tradingSvc
        accountService = accountSvc
        marketStore = market
        watchlistStore = watchlist
        tradingStore = trading
        portfolioStore = portfolio
        isReady = true
    }

    /// 选中标的或周期变化时由 ContentView 调用。
    func selectionChanged() {
        guard isReady,
              let code = watchlist.selectedCode,
              let sym = watchlist.symbol(for: code) else { return }
        syncDraft(code: code, name: sym.name)
        let tf = watchlist.selectedTimeFrame
        Task { await self.market.select(symbol: sym, timeFrame: tf) }
    }

    /// 全市场搜索。真实模式走东财 suggest，模拟模式过滤内置股票池。
    func search(_ query: String) async -> [Symbol] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard isReady, !q.isEmpty, let marketService else { return [] }
        return (try? await marketService.search(query: q, limit: 20)) ?? []
    }

    /// 搜索结果批量报价，用于下拉价格预览与过滤已退市标的。
    func previewQuotes(for codes: [String]) async -> [String: Quote] {
        guard isReady, !codes.isEmpty, let marketService else { return [:] }
        let quotes = (try? await marketService.quotes(for: codes)) ?? []
        return Dictionary(uniqueKeysWithValues: quotes.map { ($0.symbol, $0) })
    }

    /// 切换当前板块，并为还没有快照的股票补行情。
    func showBoard(_ id: UUID) {
        guard isReady else { return }
        watchlist.activate(id)
        let symbols = watchlist.codes.compactMap { watchlist.symbol(for: $0) }
        market.prepareSymbols(symbols)
        Task { await market.ensureSymbols(symbols) }
    }

    /// 删除自定义板块。删掉当前板块时回到「自选」。
    func removeBoard(_ id: UUID) {
        guard isReady else { return }
        watchlist.deleteBoard(id)
        let symbols = watchlist.codes.compactMap { watchlist.symbol(for: $0) }
        market.prepareSymbols(symbols)
        Task { await market.ensureSymbols(symbols) }
    }

    /// 搜索结果加入当前板块并选中：建档、扩展行情订阅、切换图表。
    func addToWatchlistAndSelect(_ symbol: Symbol) {
        guard isReady else { return }
        watchlist.register(symbol)
        watchlist.add(symbol.fullCode)
        market.ensureSymbol(symbol)
        watchlist.select(symbol.fullCode)
    }

    private func syncDraft(code: String, name: String) {
        let ref = market.state(for: code)?.quote?.lastPrice
        trading.draft.setSymbol(code: code, name: name, refPrice: ref)
    }
}
