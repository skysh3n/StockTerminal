import Foundation

/// 五档盘口
public struct OrderBook: Codable, Sendable, Hashable {
    public struct Level: Codable, Sendable, Hashable {
        public var price: Decimal
        public var volume: Int       // 挂单量（股）

        public init(price: Decimal, volume: Int) {
            self.price = price
            self.volume = volume
        }
    }

    public let symbol: String
    public var asks: [Level]         // 卖一..卖五（下标 0 = 卖一）
    public var bids: [Level]         // 买一..买五（下标 0 = 买一）
    public var timestamp: Date

    public init(symbol: String, asks: [Level], bids: [Level], timestamp: Date) {
        self.symbol = symbol
        self.asks = asks
        self.bids = bids
        self.timestamp = timestamp
    }

    public var bestAsk: Level? { asks.first }
    public var bestBid: Level? { bids.first }

    public var spread: Decimal? {
        guard let a = bestAsk, let b = bestBid else { return nil }
        return a.price - b.price
    }
}
