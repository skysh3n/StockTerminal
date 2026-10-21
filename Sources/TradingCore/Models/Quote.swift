import Foundation

/// 实时行情快照
public struct Quote: Codable, Sendable, Hashable {
    public let symbol: String        // 完整代码 "SH600519"
    public var lastPrice: Decimal
    public var open: Decimal
    public var high: Decimal
    public var low: Decimal
    public var preClose: Decimal
    public var bidPrice1: Decimal
    public var askPrice1: Decimal
    public var bidVolume1: Int       // 股
    public var askVolume1: Int       // 股
    public var volume: Int64         // 累计成交量（股）
    public var turnover: Decimal     // 累计成交额（元）
    public var upperLimit: Decimal   // 涨停价
    public var lowerLimit: Decimal   // 跌停价
    public var timestamp: Date

    public init(
        symbol: String, lastPrice: Decimal, open: Decimal, high: Decimal, low: Decimal,
        preClose: Decimal, bidPrice1: Decimal, askPrice1: Decimal,
        bidVolume1: Int, askVolume1: Int, volume: Int64, turnover: Decimal,
        upperLimit: Decimal, lowerLimit: Decimal, timestamp: Date
    ) {
        self.symbol = symbol
        self.lastPrice = lastPrice
        self.open = open
        self.high = high
        self.low = low
        self.preClose = preClose
        self.bidPrice1 = bidPrice1
        self.askPrice1 = askPrice1
        self.bidVolume1 = bidVolume1
        self.askVolume1 = askVolume1
        self.volume = volume
        self.turnover = turnover
        self.upperLimit = upperLimit
        self.lowerLimit = lowerLimit
        self.timestamp = timestamp
    }

    public var change: Decimal { lastPrice - preClose }

    public var changePercent: Double {
        guard preClose != 0 else { return 0 }
        return (change / preClose).doubleValue * 100
    }

    /// 振幅%
    public var amplitude: Double {
        guard preClose != 0 else { return 0 }
        return ((high - low) / preClose).doubleValue * 100
    }
}
