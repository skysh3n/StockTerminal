import Foundation

/// K线 bar 聚合器：把实时 tick 聚合进「形成中的 bar」，满 ticksPerBar 后滚动出新 bar。
/// Mock 环境对时间做了压缩（1 分钟 bar ≈ 3.75 秒真实时间），让图表「活」起来。
struct BarAggregator: Sendable {
    var bar: KLine
    let timeFrame: TimeFrame
    let ticksPerBar: Int
    /// 最多滚动出的 bar 数（分钟线一个交易日 240 根封顶）；nil 表示不限
    let maxBars: Int?
    private(set) var rolledCount: Int
    private var counter = 0

    init(bar: KLine, timeFrame: TimeFrame, ticksPerBar: Int, maxBars: Int? = nil, rolledCount: Int = 0) {
        self.bar = bar
        self.timeFrame = timeFrame
        self.ticksPerBar = ticksPerBar
        self.maxBars = maxBars
        self.rolledCount = rolledCount
    }

    /// 聚合一次成交，返回「若发生滚动，被完结的上一根 bar」
    mutating func apply(last: Decimal, volume: Int64, turnover: Decimal) -> KLine? {
        bar.close = last
        bar.high = max(bar.high, last)
        bar.low = min(bar.low, last)
        bar.volume += volume
        bar.turnover += turnover
        counter += 1

        if counter >= ticksPerBar, maxBars == nil || rolledCount < maxBars! - 1 {
            let finished = bar
            counter = 0
            rolledCount += 1
            bar = KLine(
                timestamp: Self.nextTimestamp(after: bar.timestamp, timeFrame: timeFrame),
                open: last, high: last, low: last, close: last,
                volume: 0, turnover: 0
            )
            return finished
        }
        return nil
    }

    /// 下一根 bar 的时间戳：分钟线跨午休跳 13:00，日K跳过周末，周K +7 天
    static func nextTimestamp(after ts: Date, timeFrame: TimeFrame) -> Date {
        let cal = Calendar(identifier: .gregorian)
        switch timeFrame {
        case .timeShare, .min1:
            let next = ts.addingTimeInterval(60)
            let h = cal.component(.hour, from: next)
            let m = cal.component(.minute, from: next)
            if h == 11 && m >= 30 {
                return cal.startOfDay(for: next).addingTimeInterval(13 * 3600)
            }
            return next
        case .min5:
            let next = ts.addingTimeInterval(300)
            let h = cal.component(.hour, from: next)
            let m = cal.component(.minute, from: next)
            if (h == 11 && m >= 30) || h == 12 {
                return cal.startOfDay(for: next).addingTimeInterval(13 * 3600)
            }
            return next
        case .day:
            var next = cal.date(byAdding: .day, value: 1, to: ts)!
            while [1, 7].contains(cal.component(.weekday, from: next)) {
                next = cal.date(byAdding: .day, value: 1, to: next)!
            }
            return next
        case .week:
            return ts.addingTimeInterval(7 * 86400)
        }
    }
}
