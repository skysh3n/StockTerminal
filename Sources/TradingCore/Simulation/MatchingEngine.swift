import Foundation

/// 模拟撮合引擎（actor 隔离，全部资金/持仓/委托状态在此）。
/// 规则按 A 股原型级实现：
/// - 限价单与盘口交叉立即成交，否则挂入内部簿等待现价穿越
/// - 市价单逐档吃对手盘，未成部分自动撤销
/// - 买入冻结资金、整手校验；卖出冻结股份、T+1 可卖约束
/// - 佣金/印花税/过户费；成交后加权成本更新持仓，四路回报流广播
public actor MatchingEngine {
    public struct MarketRef: Sendable {
        public var quote: Quote
        public var book: OrderBook
    }

    private let symbols: [String: Symbol]
    private let hubs: EventHubs
    private let fees = FeeSchedule()
    private var refs: [String: MarketRef] = [:]

    private let initialCash: Decimal
    private var cash: Decimal
    private var frozenCash: Decimal = 0
    /// 每笔委托当前冻结的资金
    private var orderFrozen: [String: Decimal] = [:]
    private var positions: [String: Position] = [:]
    private var orders: [String: Order] = [:]
    private var orderIds: [String] = []        // 新→旧
    private var restingIds: Set<String> = []   // 挂单等待成交
    private var tradeList: [Trade] = []        // 新→旧
    private var orderSeq = 0
    private var tradeSeq = 0
    private var lastAccountPush = Date.distantPast

    public init(symbols: [Symbol], hubs: EventHubs, initialCash: Decimal = Decimal(1_000_000)) {
        self.symbols = Dictionary(uniqueKeysWithValues: symbols.map { ($0.fullCode, $0) })
        self.hubs = hubs
        self.initialCash = initialCash
        self.cash = initialCash
    }

    // MARK: - 行情驱动

    /// 时钟每 tick 调用：更新引用价、撮合挂单、刷新持仓市值、广播账户
    public func onMarketMove(quote: Quote, book: OrderBook) {
        refs[quote.symbol] = MarketRef(quote: quote, book: book)
        matchResting(symbol: quote.symbol)
        if var pos = positions[quote.symbol] {
            pos.lastPrice = quote.lastPrice
            positions[quote.symbol] = pos
        }
        broadcastAccount()
    }

    // MARK: - 下单 / 撤单

    @discardableResult
    public func place(_ req: OrderRequest) throws -> Order {
        guard let symbol = symbols[req.symbol] else { throw ServiceError.symbolNotFound(req.symbol) }
        guard let ref = refs[req.symbol] else { throw ServiceError.backend("暂无行情，请稍后再试") }
        guard req.quantity > 0 else { throw ServiceError.invalidQuantity(req.quantity) }
        if req.side == .buy, req.quantity % symbol.lotSize != 0 {
            throw ServiceError.invalidQuantity(req.quantity)
        }

        let tick = symbol.priceTick
        var limitPrice: Decimal?
        if req.type == .limit {
            guard let p = req.price else { throw ServiceError.backend("限价单必须指定价格") }
            let lp = p.quantized(to: tick)
            if lp > ref.quote.upperLimit || lp < ref.quote.lowerLimit {
                throw ServiceError.priceOutOfLimit(lp)
            }
            limitPrice = lp
        }

        orderSeq += 1
        let id = String(format: "W%06d", orderSeq)
        var order = Order(
            id: id, clientOrderId: req.clientOrderId, symbol: req.symbol, name: symbol.name,
            side: req.side, type: req.type, price: limitPrice, quantity: req.quantity,
            status: .pending, createdAt: Date(), updatedAt: Date()
        )

        switch req.side {
        case .buy:
            let est = limitPrice ?? ref.book.bestAsk?.price ?? ref.quote.lastPrice
            let need = est * Decimal(req.quantity) * fees.freezeBufferRate + Decimal(10)
            let available = cash - frozenCash
            guard available >= need else {
                throw ServiceError.insufficientCash(required: need, available: available)
            }
            frozenCash += need
            orderFrozen[id] = need
            matchOrder(&order, ref: ref, symbol: symbol)
            settleBuyFreeze(&order, est: est)

        case .sell:
            let avail = positions[req.symbol]?.availableQuantity ?? 0
            guard avail >= req.quantity else {
                throw ServiceError.insufficientShares(required: req.quantity, available: avail)
            }
            positions[req.symbol]?.availableQuantity -= req.quantity   // 冻结股份
            matchOrder(&order, ref: ref, symbol: symbol)
            if order.remainingQuantity > 0, order.type == .market {
                // 市价单未成部分自动撤：还回冻结股份
                positions[req.symbol]?.availableQuantity += order.remainingQuantity
            }
        }

        // 状态判定
        if order.remainingQuantity == 0 {
            order.status = .filled
        } else if order.type == .market {
            order.status = order.filledQuantity > 0 ? .partialFilled : .cancelled
        } else {
            order.status = order.filledQuantity > 0 ? .partialFilled : .pending
            restingIds.insert(id)
        }

        orders[id] = order
        orderIds.insert(id, at: 0)
        hubs.orders.broadcast(order)
        broadcastAccount(force: true)
        return order
    }

    public func cancel(id: String) throws {
        guard var order = orders[id] else { throw ServiceError.orderNotFound(id) }
        guard order.status.isCancellable, restingIds.contains(id) else {
            throw ServiceError.orderNotCancellable(id)
        }
        let remain = order.remainingQuantity
        if order.side == .buy {
            frozenCash -= (orderFrozen[id] ?? 0)
            orderFrozen[id] = 0
        } else if var pos = positions[order.symbol] {
            pos.availableQuantity += remain
            positions[order.symbol] = pos
        }
        order.status = .cancelled
        order.updatedAt = Date()
        orders[id] = order
        restingIds.remove(id)
        hubs.orders.broadcast(order)
        broadcastAccount(force: true)
    }

    // MARK: - 查询

    public func snapshotNow() -> AccountSnapshot { makeSnapshot() }

    public func positionsNow() -> [Position] { positionList() }

    public func openOrders() -> [Order] {
        orderIds.compactMap { orders[$0] }.filter { $0.status.isCancellable && restingIds.contains($0.id) }
    }

    public func allOrders() -> [Order] { orderIds.compactMap { orders[$0] } }

    public func allTrades() -> [Trade] { tradeList }

    /// 供 UI 查询某标的当前可卖股数
    public func availableQuantity(symbol: String) -> Int { positions[symbol]?.availableQuantity ?? 0 }

    // MARK: - 撮合内部

    /// 用盘口深度撮合（限价交叉 / 市价吃单）
    private func matchOrder(_ order: inout Order, ref: MarketRef, symbol: Symbol) {
        var levels = order.side == .buy ? ref.book.asks : ref.book.bids
        var remaining = order.remainingQuantity
        var levelIdx = 0

        while remaining > 0, levelIdx < levels.count {
            let level = levels[levelIdx]
            if let lp = order.price {
                if order.side == .buy, level.price > lp { break }
                if order.side == .sell, level.price < lp { break }
            }
            var n = min(remaining, level.volume)
            if order.side == .buy { n = (n / symbol.lotSize) * symbol.lotSize }  // 买入按整手成交
            if n <= 0 { levelIdx += 1; continue }

            let notional = level.price * Decimal(n)
            let fee = fees.fee(side: order.side, notional: notional, exchange: symbol.exchange)
            tradeSeq += 1
            let trade = Trade(
                id: String(format: "T%06d", tradeSeq), orderId: order.id,
                symbol: order.symbol, name: order.name, side: order.side,
                price: level.price, quantity: n, fee: fee, timestamp: Date()
            )
            tradeList.insert(trade, at: 0)
            hubs.trades.broadcast(trade)

            applyFill(order: &order, trade: trade)
            remaining -= n
            levels[levelIdx].volume -= n
            if levels[levelIdx].volume <= 0 { levelIdx += 1 }
        }
    }

    /// 单笔成交入账：更新均价/现金/冻结/持仓（买入 T+1 不增可卖）
    private func applyFill(order: inout Order, trade: Trade) {
        let prevQty = order.filledQuantity
        let prevAvg = order.filledAvgPrice ?? 0
        order.filledQuantity += trade.quantity
        order.filledAvgPrice = ((prevAvg * Decimal(prevQty)) + trade.amount) / Decimal(order.filledQuantity)
        order.updatedAt = trade.timestamp

        switch order.side {
        case .buy:
            let cost = trade.amount + trade.fee
            cash -= cost
            frozenCash -= cost
            orderFrozen[order.id] = max(0, (orderFrozen[order.id] ?? 0) - cost)
            var pos = positions[order.symbol] ?? Position(
                symbol: order.symbol, name: order.name,
                quantity: 0, availableQuantity: 0, costPrice: 0, lastPrice: trade.price
            )
            let newQty = pos.quantity + trade.quantity
            // 成本价含费用加权
            pos.costPrice = ((pos.costPrice * Decimal(pos.quantity)) + cost) / Decimal(newQty)
            pos.quantity = newQty
            pos.lastPrice = trade.price
            positions[order.symbol] = pos

        case .sell:
            cash += trade.amount - trade.fee
            guard var pos = positions[order.symbol] else { return }
            pos.quantity -= trade.quantity
            pos.lastPrice = trade.price
            if pos.quantity <= 0 {
                positions[order.symbol] = nil
            } else {
                positions[order.symbol] = pos
            }
        }
    }

    /// 买单成交/收尾后校准冻结资金：挂单部分按 限价×余量 保留冻结，其余释放
    private func settleBuyFreeze(_ order: inout Order, est: Decimal) {
        let target: Decimal
        if order.remainingQuantity > 0, order.type == .limit, !order.status.isTerminal || order.status == .partialFilled {
            let basis = order.price ?? est
            target = basis * Decimal(order.remainingQuantity) * fees.freezeBufferRate + Decimal(5)
        } else {
            target = 0
        }
        let current = orderFrozen[order.id] ?? 0
        frozenCash += (target - current)
        orderFrozen[order.id] = target
    }

    /// 现价穿越挂单价 → 成交 resting 限价单
    private func matchResting(symbol code: String) {
        guard let ref = refs[code], let symbol = symbols[code] else { return }
        for id in Array(restingIds) {
            guard var order = orders[id], order.symbol == code else { continue }
            var crossed = false
            if order.side == .buy, let lp = order.price, let ask = ref.book.bestAsk, lp >= ask.price {
                crossed = true
            }
            if order.side == .sell, let lp = order.price, let bid = ref.book.bestBid, lp <= bid.price {
                crossed = true
            }
            guard crossed else { continue }

            let before = order.filledQuantity
            matchOrder(&order, ref: ref, symbol: symbol)
            guard order.filledQuantity != before else { continue }

            order.updatedAt = Date()
            if order.remainingQuantity == 0 {
                order.status = .filled
                restingIds.remove(id)
            } else {
                order.status = .partialFilled
            }
            if order.side == .buy { settleBuyFreeze(&order, est: order.price ?? ref.quote.lastPrice) }
            orders[id] = order
            hubs.orders.broadcast(order)
            broadcastAccount(force: true)
        }
    }

    // MARK: - 账户

    private func makeSnapshot() -> AccountSnapshot {
        var marketValue = Decimal.zero
        for pos in positions.values { marketValue += pos.marketValue }
        let total = cash + frozenCash + marketValue
        let dayProfit = total - initialCash
        let pct = initialCash > 0 ? (dayProfit / initialCash).doubleValue * 100 : 0
        return AccountSnapshot(
            totalAssets: total, availableCash: cash - frozenCash, marketValue: marketValue,
            frozenCash: frozenCash, totalProfit: dayProfit, dayProfit: dayProfit,
            dayProfitPercent: pct, timestamp: Date()
        )
    }

    private func positionList() -> [Position] {
        positions.values.sorted { $0.marketValue > $1.marketValue }
    }

    /// 账户广播限频（0.5s），成交/撤单强制立即广播
    private func broadcastAccount(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastAccountPush) > 0.5 else { return }
        lastAccountPush = now
        hubs.snapshots.broadcast(makeSnapshot())
        hubs.positions.broadcast(positionList())
    }
}
