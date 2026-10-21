import XCTest
@testable import TradingCore

/// 测试用流收集器（actor 隔离，Swift 6 并发安全）
private actor Collector<T> {
    private(set) var items: [T] = []
    func append(_ item: T) { items.append(item) }
}

/// 撮合引擎测试：资金/持仓/冻结/T+1/整手/涨跌停/撤单
final class MatchingEngineTests: XCTestCase {

    private let symbol = Symbol(code: "600519", exchange: .sse, name: "贵州茅台")
    private let tick = Decimal(string: "0.01")!

    private func makeEngine(cash: Decimal = Decimal(1_000_000)) -> (MatchingEngine, EventHubs) {
        let hubs = EventHubs()
        let engine = MatchingEngine(symbols: [symbol], hubs: hubs, initialCash: cash)
        return (engine, hubs)
    }

    private func makeQuote(last: Decimal) -> Quote {
        Quote(
            symbol: "SH600519", lastPrice: last, open: last, high: last, low: last,
            preClose: Decimal(1500), bidPrice1: last - tick, askPrice1: last + tick,
            bidVolume1: 10_000, askVolume1: 10_000, volume: 0, turnover: 0,
            upperLimit: Decimal(1650), lowerLimit: Decimal(1350), timestamp: Date()
        )
    }

    private func makeBook(last: Decimal, levelVolume: Int = 100_000) -> OrderBook {
        let asks = (0..<5).map { OrderBook.Level(price: last + tick * Decimal($0 + 1), volume: levelVolume) }
        let bids = (0..<5).map { OrderBook.Level(price: last - tick * Decimal($0 + 1), volume: levelVolume) }
        return OrderBook(symbol: "SH600519", asks: asks, bids: bids, timestamp: Date())
    }

    private func prime(_ engine: MatchingEngine, last: Decimal) async {
        await engine.onMarketMove(quote: makeQuote(last: last), book: makeBook(last: last))
    }

    // MARK: - 市价单

    func testMarketBuyFillsImmediately() async throws {
        let (engine, _) = makeEngine()
        await prime(engine, last: Decimal(1500))

        let req = OrderRequest(symbol: "SH600519", side: .buy, type: .market, price: nil, quantity: 200)
        let order = try await engine.place(req)

        XCTAssertEqual(order.status, .filled)
        XCTAssertEqual(order.filledQuantity, 200)
        // 成交价 = 卖一 = 1500.01
        XCTAssertEqual(order.filledAvgPrice, Decimal(string: "1500.01")!)

        let positions = await engine.positionsNow()
        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0].quantity, 200)
        XCTAssertEqual(positions[0].availableQuantity, 0, "T+1：当日买入不可卖")

        let snap = await engine.snapshotNow()
        XCTAssertLessThan(snap.availableCash, Decimal(1_000_000), "买入后现金减少")
        XCTAssertEqual(snap.frozenCash, 0, "全部成交后无冻结")
    }

    func testMarketSellRequiresPosition() async throws {
        let (engine, _) = makeEngine()
        await prime(engine, last: Decimal(1500))

        let req = OrderRequest(symbol: "SH600519", side: .sell, type: .market, price: nil, quantity: 100)
        do {
            _ = try await engine.place(req)
            XCTFail("无持仓卖出应报错")
        } catch let e as ServiceError {
            if case .insufficientShares = e {} else { XCTFail("错误类型不对: \(e)") }
        }
    }

    // MARK: - 限价单

    func testLimitBuyBelowMarketRestsThenFillsOnCross() async throws {
        let (engine, hubs) = makeEngine()
        await prime(engine, last: Decimal(1500))

        // 挂 1495 买入（低于卖一，不交叉 → 挂单）
        let req = OrderRequest(symbol: "SH600519", side: .buy, type: .limit, price: Decimal(1495), quantity: 100)
        let order = try await engine.place(req)
        XCTAssertEqual(order.status, .pending)

        let snap1 = await engine.snapshotNow()
        XCTAssertGreaterThan(snap1.frozenCash, 0, "挂单应冻结资金")

        // 收到委托回报（流在 Task 外创建：sink 同步注册，避免漏掉后续广播）
        let orderStream = hubs.orders.stream()
        let received = Collector<Order>()
        let task = Task { for await o in orderStream { await received.append(o) } }
        defer { task.cancel() }

        // 市价下移到 1494.99 → 卖一 1495.00 ≤ 限价 1495 → 应成交
        await engine.onMarketMove(quote: makeQuote(last: Decimal(string: "1494.99")!), book: makeBook(last: Decimal(string: "1494.99")!))
        try await Task.sleep(for: .milliseconds(50))

        let gotOrders = await received.items
        XCTAssertFalse(gotOrders.isEmpty, "应收到委托回报")

        let orders = await engine.allOrders()
        XCTAssertEqual(orders.first?.status, .filled, "现价穿越挂单价应成交")
        let snap2 = await engine.snapshotNow()
        XCTAssertEqual(snap2.frozenCash, 0, "成交后释放冻结")
    }

    func testLimitBuyCrossingFillsAtAsk() async throws {
        let (engine, _) = makeEngine()
        await prime(engine, last: Decimal(1500))

        // 限价 1505 买入 ≥ 卖一 1500.01 → 立即以卖一价成交
        let req = OrderRequest(symbol: "SH600519", side: .buy, type: .limit, price: Decimal(1505), quantity: 100)
        let order = try await engine.place(req)
        XCTAssertEqual(order.status, .filled)
        XCTAssertEqual(order.filledAvgPrice, Decimal(string: "1500.01")!, "成交价优于限价")
    }

    func testCancelReleasesFreeze() async throws {
        let (engine, _) = makeEngine()
        await prime(engine, last: Decimal(1500))

        let req = OrderRequest(symbol: "SH600519", side: .buy, type: .limit, price: Decimal(1400), quantity: 100)
        let order = try await engine.place(req)
        let snap1 = await engine.snapshotNow()
        XCTAssertGreaterThan(snap1.frozenCash, 0)

        try await engine.cancel(id: order.id)
        let snap2 = await engine.snapshotNow()
        XCTAssertEqual(snap2.frozenCash, 0, "撤单后解冻")
        XCTAssertEqual(snap2.availableCash, Decimal(1_000_000), "撤单资金无损")

        let orders = await engine.allOrders()
        XCTAssertEqual(orders.first?.status, .cancelled)
    }

    // MARK: - 校验

    func testBuyMustBeRoundLot() async throws {
        let (engine, _) = makeEngine()
        await prime(engine, last: Decimal(1500))
        let req = OrderRequest(symbol: "SH600519", side: .buy, type: .market, price: nil, quantity: 150)
        do {
            _ = try await engine.place(req)
            XCTFail("非整手应报错")
        } catch let e as ServiceError {
            if case .invalidQuantity = e {} else { XCTFail("错误类型不对: \(e)") }
        }
    }

    func testInsufficientCash() async throws {
        let (engine, _) = makeEngine(cash: Decimal(100_000))
        await prime(engine, last: Decimal(1500))
        // 100 股 × 1500 ≈ 15 万 > 10 万
        let req = OrderRequest(symbol: "SH600519", side: .buy, type: .market, price: nil, quantity: 100)
        do {
            _ = try await engine.place(req)
            XCTFail("资金不足应报错")
        } catch let e as ServiceError {
            if case .insufficientCash = e {} else { XCTFail("错误类型不对: \(e)") }
        }
    }

    func testPriceOutOfLimitRejected() async throws {
        let (engine, _) = makeEngine()
        await prime(engine, last: Decimal(1500))
        let req = OrderRequest(symbol: "SH600519", side: .buy, type: .limit, price: Decimal(2000), quantity: 100)
        do {
            _ = try await engine.place(req)
            XCTFail("超涨停价应报错")
        } catch let e as ServiceError {
            if case .priceOutOfLimit = e {} else { XCTFail("错误类型不对: \(e)") }
        }
    }

    // MARK: - T+1 与卖出回款

    func testSellFlowWithT1() async throws {
        let (engine, hubs) = makeEngine()
        await prime(engine, last: Decimal(1500))

        // 买入 300 股
        _ = try await engine.place(OrderRequest(symbol: "SH600519", side: .buy, type: .market, price: nil, quantity: 300))
        var positions = await engine.positionsNow()
        XCTAssertEqual(positions[0].availableQuantity, 0, "T+1 当日不可卖")

        // 手动模拟「次日」：直接放开可用（真实环境由日终清算完成）
        // 这里通过再次行情驱动无法放开，故用卖出报错验证 T+1 生效
        do {
            _ = try await engine.place(OrderRequest(symbol: "SH600519", side: .sell, type: .market, price: nil, quantity: 100))
            XCTFail("T+1 当日卖出应报错")
        } catch let e as ServiceError {
            if case .insufficientShares = e {} else { XCTFail("错误类型不对: \(e)") }
        }

        _ = hubs // 保持引用
        positions = await engine.positionsNow()
        XCTAssertEqual(positions[0].quantity, 300)
    }

    func testTradeAndSnapshotBroadcast() async throws {
        let (engine, hubs) = makeEngine()
        await prime(engine, last: Decimal(1500))

        let tradeStream = hubs.trades.stream()
        let snapStream = hubs.snapshots.stream()
        let tradeCollector = Collector<Trade>()
        let snapCollector = Collector<AccountSnapshot>()
        let t1 = Task { for await t in tradeStream { await tradeCollector.append(t) } }
        let t2 = Task { for await s in snapStream { await snapCollector.append(s) } }
        defer { t1.cancel(); t2.cancel() }

        _ = try await engine.place(OrderRequest(symbol: "SH600519", side: .buy, type: .market, price: nil, quantity: 100))
        try await Task.sleep(for: .milliseconds(50))

        let trades = await tradeCollector.items
        let snaps = await snapCollector.items
        XCTAssertEqual(trades.count, 1)
        XCTAssertEqual(trades.first?.quantity, 100)
        XCTAssertGreaterThan(trades.first?.fee ?? 0, 0, "应收佣金")
        XCTAssertFalse(snaps.isEmpty, "应收到资产快照广播")
    }
}
