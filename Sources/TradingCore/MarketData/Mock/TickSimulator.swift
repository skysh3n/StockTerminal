import Foundation

/// 逐笔成交模拟：每个 tick 生成 1~3 笔，价格取买一/卖一/中间价，方向据此判定内外盘。
public enum TickSimulator {

    public static func make(
        symbol: String,
        book: OrderBook,
        rng: inout SplitMix64,
        seq: inout UInt64,
        now: Date
    ) -> [Tick] {
        let count = 1 + Int(rng.unitDouble() * 3)
        var out: [Tick] = []
        out.reserveCapacity(count)
        let tick = Decimal(string: "0.01")!

        for _ in 0..<count {
            let r = rng.unitDouble()
            var direction: TickDirection = .neutral
            var price: Decimal

            if r < 0.42, let ask = book.bestAsk {
                direction = .buy       // 主动买 → 外盘
                price = ask.price
            } else if r < 0.84, let bid = book.bestBid {
                direction = .sell      // 主动卖 → 内盘
                price = bid.price
            } else {
                direction = .neutral
                let mid = ((book.bestAsk?.price ?? 0) + (book.bestBid?.price ?? 0)) / 2
                price = mid.quantized(to: tick)
            }

            // 手数：多数 1~60 手，偶发大单
            var lots = 1 + Int(rng.unitDouble() * 60)
            if rng.unitDouble() < 0.06 { lots += Int(rng.unitDouble() * 400) }

            seq += 1
            out.append(Tick(
                id: seq, symbol: symbol, price: price, volume: lots * 100,
                direction: direction, timestamp: now
            ))
        }
        return out
    }
}
