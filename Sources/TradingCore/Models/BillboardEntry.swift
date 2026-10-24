import Foundation

/// 龙虎榜条目（公开 datacenter 接口）。
public struct BillboardEntry: Sendable, Hashable, Identifiable {
    public var id: String { "\(symbol.fullCode)-\(tradeDate)" }
    public let symbol: Symbol
    public let closePrice: Decimal
    public let changePercent: Double
    public let netAmount: Decimal       // 龙虎榜净买额（元）
    public let explanation: String
    public let tradeDate: String

    public init(
        symbol: Symbol,
        closePrice: Decimal,
        changePercent: Double,
        netAmount: Decimal,
        explanation: String,
        tradeDate: String
    ) {
        self.symbol = symbol
        self.closePrice = closePrice
        self.changePercent = changePercent
        self.netAmount = netAmount
        self.explanation = explanation
        self.tradeDate = tradeDate
    }
}

/// 个股主力/散户资金流快照（公开 fflow 接口近似）。
public struct FundFlowSnapshot: Sendable, Hashable {
    public let symbol: String
    public let mainNetInflow: Decimal    // 主力净流入（元）
    public let retailNetInflow: Decimal  // 散户净流入近似（元）
    public let asOf: Date

    public init(symbol: String, mainNetInflow: Decimal, retailNetInflow: Decimal, asOf: Date) {
        self.symbol = symbol
        self.mainNetInflow = mainNetInflow
        self.retailNetInflow = retailNetInflow
        self.asOf = asOf
    }
}
