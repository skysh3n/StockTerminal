import Foundation

/// 市场时钟（actor）：Mock 行情的心脏。
/// 每 tick（默认 250ms，4Hz）推进全部标的的随机游走，派生盘口/逐笔，
/// 聚合各周期 K 线 bar，并通过 BroadcastHub 广播给所有订阅者；
/// 同时驱动撮合引擎（现价穿越挂单价 → 成交）。
public actor MarketClock {

    private struct SymState {
        var rng: SplitMix64
        var walk: RandomWalk
        var quote: Quote
        var book: OrderBook
        var history: SymbolHistory
        var tickSeq: UInt64 = 0
        var minuteAgg: BarAggregator   // 分时 & 1分 共用
        var min5Agg: BarAggregator
        var dayAgg: BarAggregator
    }

    private var states: [String: SymState] = [:]
    private let symbolList: [Symbol]
    private let hubs: EventHubs
    private let matching: MatchingEngine
    private let interval: Duration
    private var loopTask: Task<Void, Never>?
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    /// Mock 时间压缩：1 分钟 bar = 15 tick ≈ 3.75 秒真实时间
    private static let ticksPerMinuteBar = 15

    public init(
        universe: [UniverseEntry],
        hubs: EventHubs,
        matching: MatchingEngine,
        seed: UInt64 = 20261017,
        interval: Duration = .milliseconds(250),
        now: Date = Date()
    ) {
        self.symbolList = universe.map(\.symbol)
        self.hubs = hubs
        self.matching = matching
        self.interval = interval

        for entry in universe {
            let s = entry.symbol
            let code = s.fullCode
            // 每只股票独立种子：同一次运行走势可复现
            let symSeed = seed ^ (fnv1a64(code) &* 0x9E37_79B9_7F4A_7C15)
            let history = HistoryGenerator.build(symbol: s, seed: symSeed, basePrice: entry.basePrice, now: now)

            var rng = SplitMix64(seed: symSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407)
            let walk = RandomWalk(
                price: history.lastPrice, preClose: history.preClose,
                upperLimit: history.upperLimit, lowerLimit: history.lowerLimit,
                tick: s.priceTick
            )
            let book = OrderBookSimulator.make(symbol: code, last: history.lastPrice, tick: s.priceTick, rng: &rng)
            let volSoFar = history.timeShare.reduce(Int64(0)) { $0 + $1.volume }
            let toSoFar = history.timeShare.reduce(Decimal.zero) { $0 + $1.turnover }
            let quote = Quote(
                symbol: code,
                lastPrice: history.lastPrice,
                open: history.openToday,
                high: history.daySeed.high,
                low: history.daySeed.low,
                preClose: history.preClose,
                bidPrice1: book.bestBid?.price ?? history.lastPrice,
                askPrice1: book.bestAsk?.price ?? history.lastPrice,
                bidVolume1: book.bestBid?.volume ?? 0,
                askVolume1: book.bestAsk?.volume ?? 0,
                volume: volSoFar,
                turnover: toSoFar,
                upperLimit: history.upperLimit,
                lowerLimit: history.lowerLimit,
                timestamp: now
            )

            let minuteAgg = BarAggregator(
                bar: history.minuteSeed, timeFrame: .min1,
                ticksPerBar: Self.ticksPerMinuteBar, maxBars: 240,
                rolledCount: history.elapsedMinutes
            )
            let min5Agg = BarAggregator(
                bar: history.min5Seed, timeFrame: .min5,
                ticksPerBar: Self.ticksPerMinuteBar * 5
            )
            let dayAgg = BarAggregator(
                bar: history.daySeed, timeFrame: .day,
                ticksPerBar: 100_000
            )

            states[code] = SymState(
                rng: rng, walk: walk, quote: quote, book: book, history: history,
                minuteAgg: minuteAgg, min5Agg: min5Agg, dayAgg: dayAgg
            )
        }
    }

    /// 启动时钟循环（幂等）
    public func start() async {
        guard loopTask == nil else { return }
        await tickOnce()   // 立即产出第一帧，UI 无需等待
        let iv = interval
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: iv)
                guard !Task.isCancelled else { break }
                await self?.tickOnce()
            }
        }
    }

    /// nonisolated 便捷启动（工厂里同步调用）
    public nonisolated func kickOff() {
        Task { await self.start() }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - 查询（供 MockMarketDataService 转发）

    public func universe() -> [Symbol] { symbolList }

    public func quotesSnapshot(for codes: [String]) -> [Quote] {
        if codes.isEmpty { return states.values.map(\.quote) }
        return codes.compactMap { states[$0]?.quote }
    }

    public func book(symbol: String) -> OrderBook? { states[symbol]?.book }

    public func preClose(symbol: String) -> Decimal? { states[symbol]?.quote.preClose }

    /// 历史 K 线（含形成中的尾部 bar）
    public func history(symbol: String, timeFrame: TimeFrame, count: Int) -> [KLine] {
        guard let st = states[symbol] else { return [] }
        switch timeFrame {
        case .timeShare, .min1:
            return Array((st.history.timeShare + [st.minuteAgg.bar]).suffix(count))
        case .min5:
            return Array((st.history.min5 + [st.min5Agg.bar]).suffix(count))
        case .day:
            return Array((st.history.day + [st.dayAgg.bar]).suffix(count))
        case .week:
            var forming = st.dayAgg.bar
            forming = KLine(
                timestamp: HistoryGenerator.startOfWeek(forming.timestamp, cal: cal),
                open: forming.open, high: forming.high, low: forming.low, close: forming.close,
                volume: forming.volume, turnover: forming.turnover
            )
            let base: [KLine]
            if let ws = st.history.weekSeed, let merged = HistoryGenerator.mergeBars([ws, forming], at: ws.timestamp) {
                base = st.history.week + [merged]
            } else {
                base = st.history.week + [forming]
            }
            return Array(base.suffix(count))
        }
    }

    // MARK: - 时钟推进

    private func tickOnce() async {
        let now = Date()
        for symbol in symbolList {
            let code = symbol.fullCode
            guard var st = states[code] else { continue }

            // 1) 价格随机游走
            let last = st.walk.step(rng: &st.rng)

            // 2) 盘口 & 逐笔
            st.book = OrderBookSimulator.make(
                symbol: code, last: last, tick: symbol.priceTick, rng: &st.rng, prev: st.book
            )
            let newTicks = TickSimulator.make(symbol: code, book: st.book, rng: &st.rng, seq: &st.tickSeq, now: now)
            let tickVol = newTicks.reduce(0) { $0 + $1.volume }
            let tickAmt = newTicks.reduce(Decimal.zero) { $0 + $1.price * Decimal($1.volume) }

            // 3) 行情快照聚合
            st.quote.lastPrice = last
            st.quote.high = max(st.quote.high, last)
            st.quote.low = min(st.quote.low, last)
            st.quote.volume += Int64(tickVol)
            st.quote.turnover += tickAmt
            st.quote.bidPrice1 = st.book.bestBid?.price ?? last
            st.quote.askPrice1 = st.book.bestAsk?.price ?? last
            st.quote.bidVolume1 = st.book.bestBid?.volume ?? 0
            st.quote.askVolume1 = st.book.bestAsk?.volume ?? 0
            st.quote.timestamp = now

            // 4) K 线聚合（分时/1分共用分钟 bar）
            let vol64 = Int64(tickVol)
            if let finished = st.minuteAgg.apply(last: last, volume: vol64, turnover: tickAmt) {
                st.history.timeShare.append(finished)
            }
            if let finished5 = st.min5Agg.apply(last: last, volume: vol64, turnover: tickAmt) {
                st.history.min5.append(finished5)
            }
            if let finishedDay = st.dayAgg.apply(last: last, volume: vol64, turnover: tickAmt) {
                st.history.day.append(finishedDay)
            }

            states[code] = st

            // 5) 广播
            hubs.quotes.broadcast(st.quote)
            hubs.books.broadcast(st.book)
            for t in newTicks { hubs.ticks.broadcast(t) }
            hubs.klines.broadcast(KLineUpdate(symbol: code, timeFrame: .timeShare, bar: st.minuteAgg.bar))
            hubs.klines.broadcast(KLineUpdate(symbol: code, timeFrame: .min1, bar: st.minuteAgg.bar))
            hubs.klines.broadcast(KLineUpdate(symbol: code, timeFrame: .min5, bar: st.min5Agg.bar))
            hubs.klines.broadcast(KLineUpdate(symbol: code, timeFrame: .day, bar: st.dayAgg.bar))

            // 6) 驱动撮合（现价穿越挂单价 → 成交；持仓市值刷新）
            await matching.onMarketMove(quote: st.quote, book: st.book)
        }
    }
}
