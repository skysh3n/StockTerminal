import Foundation

/// 证券基本信息
public struct Symbol: Codable, Sendable, Hashable, Identifiable {
    public var id: String { fullCode }
    public let code: String          // "600519"
    public let exchange: Exchange
    public let name: String          // "贵州茅台"
    public let lotSize: Int          // 每手股数，A股 = 100
    public let priceTick: Decimal    // 最小变动价位 = 0.01

    /// 完整代码，如 "SH600519"
    public var fullCode: String { "\(exchange.rawValue)\(code)" }

    /// 涨跌停幅度：创业板(300/301)/科创板(688) ±20%，北交所 ±30%，其余主板 ±10%
    public var limitRate: Decimal {
        if code.hasPrefix("300") || code.hasPrefix("301") || code.hasPrefix("688") {
            return Decimal(string: "0.2")!
        }
        if code.hasPrefix("4") || code.hasPrefix("8") || code.hasPrefix("92") {
            return Decimal(string: "0.3")!
        }
        return Decimal(string: "0.1")!
    }

    public init(
        code: String,
        exchange: Exchange,
        name: String,
        lotSize: Int = 100,
        priceTick: Decimal = Decimal(string: "0.01")!
    ) {
        self.code = code
        self.exchange = exchange
        self.name = name
        self.lotSize = lotSize
        self.priceTick = priceTick
    }
}
