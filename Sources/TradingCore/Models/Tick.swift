import Foundation

/// 逐笔成交
public struct Tick: Codable, Sendable, Hashable, Identifiable {
    public let id: UInt64            // 单调递增序号
    public let symbol: String
    public let price: Decimal
    public let volume: Int           // 本笔量（股）
    public let direction: TickDirection
    public let timestamp: Date

    public init(id: UInt64, symbol: String, price: Decimal, volume: Int, direction: TickDirection, timestamp: Date) {
        self.id = id
        self.symbol = symbol
        self.price = price
        self.volume = volume
        self.direction = direction
        self.timestamp = timestamp
    }
}
