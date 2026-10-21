import Foundation

/// 持仓
public struct Position: Codable, Sendable, Hashable, Identifiable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public var quantity: Int              // 总持仓（股）
    public var availableQuantity: Int     // 可卖（T+1：当日买入不计入）
    public var costPrice: Decimal         // 成本价（买入加权，含费用简化）
    public var lastPrice: Decimal         // 最新价

    public init(symbol: String, name: String, quantity: Int, availableQuantity: Int, costPrice: Decimal, lastPrice: Decimal) {
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.availableQuantity = availableQuantity
        self.costPrice = costPrice
        self.lastPrice = lastPrice
    }

    public var marketValue: Decimal { lastPrice * Decimal(quantity) }
    public var profit: Decimal { (lastPrice - costPrice) * Decimal(quantity) }

    public var profitPercent: Double {
        guard costPrice != 0 else { return 0 }
        return ((lastPrice - costPrice) / costPrice).doubleValue * 100
    }
}

/// 账户资产快照
public struct AccountSnapshot: Codable, Sendable, Hashable {
    public var totalAssets: Decimal       // 总资产 = 可用 + 冻结 + 市值
    public var availableCash: Decimal     // 可用资金
    public var marketValue: Decimal       // 持仓市值
    public var frozenCash: Decimal        // 挂单冻结
    public var totalProfit: Decimal       // 累计盈亏（相对初始资金）
    public var dayProfit: Decimal         // 当日盈亏（原型中与累计相同）
    public var dayProfitPercent: Double
    public var timestamp: Date

    public init(totalAssets: Decimal, availableCash: Decimal, marketValue: Decimal, frozenCash: Decimal, totalProfit: Decimal, dayProfit: Decimal, dayProfitPercent: Double, timestamp: Date) {
        self.totalAssets = totalAssets
        self.availableCash = availableCash
        self.marketValue = marketValue
        self.frozenCash = frozenCash
        self.totalProfit = totalProfit
        self.dayProfit = dayProfit
        self.dayProfitPercent = dayProfitPercent
        self.timestamp = timestamp
    }
}
