import Foundation

/// 单根 K 线（OHLCV）
public struct KLine: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64 { Int64(timestamp.timeIntervalSince1970) }
    public let timestamp: Date       // 周期起始时间（日K为当日，周K为周起始）
    public var open: Decimal
    public var high: Decimal
    public var low: Decimal
    public var close: Decimal
    public var volume: Int64         // 股
    public var turnover: Decimal

    public init(timestamp: Date, open: Decimal, high: Decimal, low: Decimal, close: Decimal, volume: Int64, turnover: Decimal) {
        self.timestamp = timestamp
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.turnover = turnover
    }

    public var isUp: Bool { close >= open }
}
