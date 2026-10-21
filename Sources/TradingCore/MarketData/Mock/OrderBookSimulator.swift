import Foundation

/// 五档盘口模拟：以最新价为中心派生买卖五档，档位量与前一帧混合保证演化连续。
public enum OrderBookSimulator {

    public static func make(
        symbol: String,
        last: Decimal,
        tick: Decimal,
        rng: inout SplitMix64,
        prev: OrderBook? = nil
    ) -> OrderBook {
        // 最新价落在买一还是卖一（模拟主动买/主动卖后的盘口形态）
        let buyOnTop = rng.unitDouble() < 0.5

        var bids: [OrderBook.Level] = []
        var asks: [OrderBook.Level] = []
        bids.reserveCapacity(5)
        asks.reserveCapacity(5)

        for i in 0..<5 {
            let bidPrice = last - tick * Decimal(buyOnTop ? i : i + 1)
            let askPrice = last + tick * Decimal(buyOnTop ? i + 1 : i)
            if bidPrice > 0 {
                let newVol = baseVolume(depth: i, rng: &rng)
                let vol = blend(newVol, price: bidPrice, prevLevels: prev?.bids)
                bids.append(OrderBook.Level(price: bidPrice, volume: vol))
            }
            let newAskVol = baseVolume(depth: i, rng: &rng)
            let askVol = blend(newAskVol, price: askPrice, prevLevels: prev?.asks)
            asks.append(OrderBook.Level(price: askPrice, volume: askVol))
        }

        // 保证卖价始终高于买价（bidPrice <= 0 截断时也不会交叉）
        if let b1 = bids.first, let a1 = asks.first, a1.price <= b1.price {
            asks = bids.first.map { top in
                (0..<5).map { i in
                    OrderBook.Level(price: top.price + tick * Decimal(i + 1), volume: baseVolume(depth: i, rng: &rng))
                }
            } ?? asks
        }

        return OrderBook(symbol: symbol, asks: asks, bids: bids, timestamp: Date())
    }

    private static func baseVolume(depth: Int, rng: inout SplitMix64) -> Int {
        // 20~420 手，深档略厚，转成股
        let lots = Int(rng.range(20, 420) * (1 + Double(depth) * 0.28))
        return lots * 100
    }

    private static func blend(_ newVol: Int, price: Decimal, prevLevels: [OrderBook.Level]?) -> Int {
        if let same = prevLevels?.first(where: { $0.price == price }) {
            return Int(Double(same.volume) * 0.6 + Double(newVol) * 0.4)
        }
        return newVol
    }
}
