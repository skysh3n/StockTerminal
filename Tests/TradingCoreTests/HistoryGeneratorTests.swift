import XCTest
@testable import TradingCore

final class HistoryGeneratorTests: XCTestCase {

    private func buildHistory(seed: UInt64 = 42) -> SymbolHistory {
        let symbol = Symbol(code: "600519", exchange: .sse, name: "贵州茅台")
        return HistoryGenerator.build(symbol: symbol, seed: seed, basePrice: Decimal(1500), now: Date())
    }

    func testDailyCount() {
        let h = buildHistory()
        XCTAssertEqual(h.day.count, 380)
    }

    func testOHLCConsistency() {
        let h = buildHistory(seed: 7)
        let all = h.day + h.week + h.timeShare + h.min5 + [h.daySeed, h.minuteSeed, h.min5Seed]
        for bar in all {
            XCTAssertGreaterThanOrEqual(bar.high, bar.open, "high ≥ open")
            XCTAssertGreaterThanOrEqual(bar.high, bar.close, "high ≥ close")
            XCTAssertLessThanOrEqual(bar.low, bar.open, "low ≤ open")
            XCTAssertLessThanOrEqual(bar.low, bar.close, "low ≤ close")
            XCTAssertGreaterThanOrEqual(bar.high, bar.low, "high ≥ low")
            XCTAssertGreaterThanOrEqual(bar.volume, 0)
            XCTAssertGreaterThan(bar.close, 0)
        }
    }

    func testDeterministicWithSameSeed() {
        let a = buildHistory(seed: 123)
        let b = buildHistory(seed: 123)
        XCTAssertEqual(a.day.last?.close, b.day.last?.close)
        XCTAssertEqual(a.lastPrice, b.lastPrice)
        XCTAssertEqual(a.preClose, b.preClose)
    }

    func testLastPriceWithinLimits() {
        let h = buildHistory(seed: 5)
        XCTAssertLessThanOrEqual(h.lastPrice, h.upperLimit)
        XCTAssertGreaterThanOrEqual(h.lastPrice, h.lowerLimit)
        // 涨跌停 = 昨收 ±10%（主板）
        let expectedUpper = (h.preClose * Decimal(string: "1.1")!).quantized(to: Decimal(string: "0.01")!)
        XCTAssertEqual(h.upperLimit, expectedUpper)
    }

    func testTimeShareChronological() {
        let h = buildHistory(seed: 11)
        let ts = h.timeShare
        XCTAssertGreaterThan(ts.count, 0)
        for i in 1..<ts.count {
            XCTAssertGreaterThan(ts[i].timestamp, ts[i - 1].timestamp, "分时序列时间递增")
        }
    }

    func testConvergenceAcrossTimeFrames() {
        // 各周期数据收敛于同一当前价
        let h = buildHistory(seed: 3)
        XCTAssertEqual(h.daySeed.close, h.lastPrice)
        XCTAssertEqual(h.minuteSeed.open, h.lastPrice)
        XCTAssertEqual(h.min5Seed.close, h.lastPrice)
    }

    func testSessionTimeSkipsLunch() {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: Date())
        let t119 = HistoryGenerator.sessionTime(minuteIndex: 119, day: day, cal: cal)
        let t120 = HistoryGenerator.sessionTime(minuteIndex: 120, day: day, cal: cal)
        XCTAssertEqual(cal.component(.hour, from: t119), 11)
        XCTAssertEqual(cal.component(.minute, from: t119), 29)
        XCTAssertEqual(cal.component(.hour, from: t120), 13)
        XCTAssertEqual(cal.component(.minute, from: t120), 0)
    }
}

final class RandomWalkTests: XCTestCase {
    func testPriceStaysWithinLimits() {
        let tick = Decimal(string: "0.01")!
        var rng = SplitMix64(seed: 2024)
        var walk = RandomWalk(
            price: Decimal(10), preClose: Decimal(10),
            upperLimit: Decimal(11), lowerLimit: Decimal(9), tick: tick
        )
        for _ in 0..<50_000 {
            let p = walk.step(rng: &rng)
            XCTAssertLessThanOrEqual(p, Decimal(11))
            XCTAssertGreaterThanOrEqual(p, Decimal(9))
            // 按 tick 取整
            XCTAssertEqual(p, p.quantized(to: tick))
        }
    }
}

final class BarAggregatorTests: XCTestCase {
    func testRollAfterTicksPerBar() {
        let bar = KLine(timestamp: Date(), open: 10, high: 10, low: 10, close: 10, volume: 0, turnover: 0)
        var agg = BarAggregator(bar: bar, timeFrame: .min1, ticksPerBar: 3)
        XCTAssertNil(agg.apply(last: 11, volume: 100, turnover: 1100))
        XCTAssertNil(agg.apply(last: 12, volume: 100, turnover: 1200))
        let finished = agg.apply(last: 13, volume: 100, turnover: 1300)
        XCTAssertNotNil(finished, "第 3 个 tick 后应滚动")
        XCTAssertEqual(finished?.close, 13)
        XCTAssertEqual(finished?.volume, 300)
        XCTAssertEqual(agg.bar.volume, 0, "新 bar 从零开始")
        XCTAssertEqual(agg.bar.open, 13, "新 bar 开盘 = 上一收盘")
    }

    func testMaxBarsStopsRolling() {
        let bar = KLine(timestamp: Date(), open: 10, high: 10, low: 10, close: 10, volume: 0, turnover: 0)
        var agg = BarAggregator(bar: bar, timeFrame: .min1, ticksPerBar: 1, maxBars: 2, rolledCount: 1)
        XCTAssertNil(agg.apply(last: 11, volume: 1, turnover: 11), "已达 maxBars，不再滚动")
        XCTAssertEqual(agg.bar.close, 11)
    }
}
