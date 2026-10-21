import Foundation

/// 真实报价 → 模拟撮合引擎的桥。
/// 真实行情接入后，模拟交易引擎需要以真实最新价/盘口驱动（持仓市值刷新、挂单撮合、市价成交），
/// 本桥把 MarketDataService 的报价流翻译成 onMarketMove 调用。
/// 报价只有一档买卖价，深档用一档价 ± tick 合成（仅用于撮合与展示，不冒充真实深度）。
public final class QuoteBridge: @unchecked Sendable {
    private let engine: MatchingEngine
    private let market: any MarketDataService
    private let symbolsByCode: [String: Symbol]
    private var task: Task<Void, Never>?

    public init(engine: MatchingEngine, market: any MarketDataService, symbols: [Symbol]) {
        self.engine = engine
        self.market = market
        self.symbolsByCode = Dictionary(uniqueKeysWithValues: symbols.map { ($0.fullCode, $0) })
    }

    public func start() {
        guard task == nil else { return }
        let stream = market.subscribeQuotes(symbols: symbolsByCode.keys.map { $0 })
        let engine = self.engine
        let byCode = self.symbolsByCode
        task = Task {
            for await q in stream {
                guard let sym = byCode[q.symbol] else { continue }
                let book = Self.syntheticBook(for: q, tick: sym.priceTick)
                await engine.onMarketMove(quote: q, book: book)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// 由一档买卖合成五档（仅供模拟撮合的流动性估计）
    static func syntheticBook(for q: Quote, tick: Decimal) -> OrderBook {
        let ask1 = q.askPrice1 > 0 ? q.askPrice1 : q.lastPrice
        let bid1 = q.bidPrice1 > 0 ? q.bidPrice1 : q.lastPrice
        let askVol = max(q.askVolume1, 1_000)
        let bidVol = max(q.bidVolume1, 1_000)
        var asks: [OrderBook.Level] = []
        var bids: [OrderBook.Level] = []
        for i in 0..<5 {
            asks.append(.init(price: ask1 + tick * Decimal(i), volume: askVol * (1 + i)))
            bids.append(.init(price: max(bid1 - tick * Decimal(i), tick), volume: bidVol * (1 + i)))
        }
        return OrderBook(symbol: q.symbol, asks: asks, bids: bids, timestamp: q.timestamp)
    }
}
