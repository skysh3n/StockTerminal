import Foundation

/// 行情榜单条目（涨幅 / 跌幅 / 成交额 / 换手 / 振幅等）。
public struct MarketRankItem: Sendable, Hashable, Identifiable {
    public var id: String { symbol.fullCode }
    public let symbol: Symbol
    public let lastPrice: Decimal
    public let changePercent: Double
    public let change: Decimal
    public let volumeLots: Int64       // 手
    public let turnover: Decimal       // 元
    /// 换手率 %（接口有则填，否则 0）
    public let turnoverRate: Double
    /// 振幅 %（接口有则填，否则 0）
    public let amplitude: Double

    public init(
        symbol: Symbol,
        lastPrice: Decimal,
        changePercent: Double,
        change: Decimal,
        volumeLots: Int64,
        turnover: Decimal,
        turnoverRate: Double = 0,
        amplitude: Double = 0
    ) {
        self.symbol = symbol
        self.lastPrice = lastPrice
        self.changePercent = changePercent
        self.change = change
        self.volumeLots = volumeLots
        self.turnover = turnover
        self.turnoverRate = turnoverRate
        self.amplitude = amplitude
    }
}

/// 榜单排序维度。
public enum MarketRankKind: String, Sendable, CaseIterable, Identifiable {
    case gainers
    case losers
    case turnover
    case turnoverRate
    case amplitude

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .gainers: return "涨幅"
        case .losers: return "跌幅"
        case .turnover: return "成交额"
        case .turnoverRate: return "换手"
        case .amplitude: return "振幅"
        }
    }
}
