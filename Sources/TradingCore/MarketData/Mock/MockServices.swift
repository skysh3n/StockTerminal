import Foundation

/// MarketDataService 的 Mock 实现：转发到 MarketClock（快照/历史）与 BroadcastHub（流订阅）。
public struct MockMarketDataService: MarketDataService {
    private let clock: MarketClock
    private let hubs: EventHubs

    public init(clock: MarketClock, hubs: EventHubs) {
        self.clock = clock
        self.hubs = hubs
    }

    public func universe() async throws -> [Symbol] {
        await clock.universe()
    }

    public func search(query: String, limit: Int) async throws -> [Symbol] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return await clock.universe().filter {
            $0.code.contains(q)
                || $0.fullCode.localizedCaseInsensitiveContains(q)
                || $0.name.localizedCaseInsensitiveContains(q)
        }.prefix(limit).map { $0 }
    }

    public func quotes(for symbols: [String]) async throws -> [Quote] {
        await clock.quotesSnapshot(for: symbols)
    }

    public func history(symbol: String, timeFrame: TimeFrame, count: Int) async throws -> [KLine] {
        await clock.history(symbol: symbol, timeFrame: timeFrame, count: count)
    }

    public func orderBook(symbol: String) async throws -> OrderBook {
        guard let book = await clock.book(symbol: symbol) else {
            throw ServiceError.symbolNotFound(symbol)
        }
        return book
    }

    public func subscribeQuotes(symbols: [String]) -> AsyncStream<Quote> {
        let set = Set(symbols)
        return hubs.quotes.stream(bufferingPolicy: .bufferingNewest(1)) { set.contains($0.symbol) }
    }

    public func subscribeKLine(symbol: String, timeFrame: TimeFrame) -> AsyncStream<KLine> {
        hubs.klines.subscribe(bufferingPolicy: .bufferingNewest(1)) { update in
            (update.symbol == symbol && update.timeFrame == timeFrame) ? update.bar : nil
        }
    }

    public func subscribeOrderBook(symbol: String) -> AsyncStream<OrderBook> {
        hubs.books.stream(bufferingPolicy: .bufferingNewest(1)) { $0.symbol == symbol }
    }

    public func subscribeTicks(symbol: String) -> AsyncStream<Tick> {
        hubs.ticks.stream(bufferingPolicy: .bufferingNewest(64)) { $0.symbol == symbol }
    }
}

/// TradingService 的 Mock 实现：转发到撮合引擎。
public struct MockTradingService: TradingService {
    private let engine: MatchingEngine
    private let hubs: EventHubs

    public init(engine: MatchingEngine, hubs: EventHubs) {
        self.engine = engine
        self.hubs = hubs
    }

    @discardableResult
    public func placeOrder(_ request: OrderRequest) async throws -> Order {
        try await engine.place(request)
    }

    public func cancelOrder(id: String) async throws {
        try await engine.cancel(id: id)
    }

    public func openOrders() async throws -> [Order] {
        await engine.openOrders()
    }

    public func allOrders() async throws -> [Order] {
        await engine.allOrders()
    }

    public func trades() async throws -> [Trade] {
        await engine.allTrades()
    }

    public func subscribeOrderUpdates() -> AsyncStream<Order> {
        hubs.orders.stream()
    }

    public func subscribeTradeUpdates() -> AsyncStream<Trade> {
        hubs.trades.stream()
    }
}

/// AccountService 的 Mock 实现：转发到撮合引擎的账户状态。
public struct MockAccountService: AccountService {
    private let engine: MatchingEngine
    private let hubs: EventHubs

    public init(engine: MatchingEngine, hubs: EventHubs) {
        self.engine = engine
        self.hubs = hubs
    }

    public func snapshot() async throws -> AccountSnapshot {
        await engine.snapshotNow()
    }

    public func positions() async throws -> [Position] {
        await engine.positionsNow()
    }

    public func subscribeSnapshot() -> AsyncStream<AccountSnapshot> {
        hubs.snapshots.stream(bufferingPolicy: .bufferingNewest(1))
    }

    public func subscribePositions() -> AsyncStream<[Position]> {
        hubs.positions.stream(bufferingPolicy: .bufferingNewest(1))
    }
}

/// Mock 服务集
public struct MockServices: Sendable {
    public let market: MockMarketDataService
    public let trading: MockTradingService
    public let account: MockAccountService
    /// 时钟引用：发车时机由组合根决定（在线模式不启动，零浪费）
    public let clock: MarketClock
}

/// 模拟行情工厂：一次创建时钟、撮合引擎和三个服务。
/// 仅在探测真实行情失败时由组合根调用。`startClock: false` 留给测试自行发车。
public enum MockFactory {
    public static func make(
        seed: UInt64 = 20261017,
        initialCash: Decimal = Decimal(1_000_000),
        interval: Duration = .milliseconds(250),
        startClock: Bool = true
    ) -> MockServices {
        let hubs = EventHubs()
        let universe = MockSymbolUniverse.entries
        let engine = MatchingEngine(symbols: universe.map(\.symbol), hubs: hubs, initialCash: initialCash)
        let clock = MarketClock(universe: universe, hubs: hubs, matching: engine, seed: seed, interval: interval)
        if startClock { clock.kickOff() }
        return MockServices(
            market: MockMarketDataService(clock: clock, hubs: hubs),
            trading: MockTradingService(engine: engine, hubs: hubs),
            account: MockAccountService(engine: engine, hubs: hubs),
            clock: clock
        )
    }
}
