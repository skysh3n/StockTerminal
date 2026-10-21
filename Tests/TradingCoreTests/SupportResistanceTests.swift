import XCTest
@testable import TradingCore

final class SupportResistanceTests: XCTestCase {

    /// 构造合成 bar 序列：基准 100，可注入指定下标的极值
    private func makeBars(
        count: Int,
        spikes: [Int: (high: Double, low: Double, close: Double)] = [:]
    ) -> [KLine] {
        (0..<count).map { i in
            let s = spikes[i]
            let high = Decimal(s?.high ?? 101)
            let low = Decimal(s?.low ?? 99)
            let close = Decimal(s?.close ?? 100)
            let open = Decimal(100)
            return KLine(
                timestamp: Date(timeIntervalSince1970: TimeInterval(i * 60)),
                open: open, high: max(high, max(open, close)), low: min(low, min(open, close)),
                close: close, volume: 1000, turnover: 100_000
            )
        }
    }

    func testFindsClearSwingHighAndLow() {
        var spikes: [Int: (high: Double, low: Double, close: Double)] = [:]
        spikes[20] = (110, 100.5, 102)   // 摆动高点
        spikes[40] = (99.5, 90, 98)      // 摆动低点
        let bars = makeBars(count: 70, spikes: spikes)
        let levels = SupportResistance.levels(bars: bars)

        let res = levels.filter { $0.kind == .resistance }
        let sup = levels.filter { $0.kind == .support }
        XCTAssertFalse(res.isEmpty, "应识别到压力位")
        XCTAssertFalse(sup.isEmpty, "应识别到支撑位")
        XCTAssertEqual(res.first!.price, 110, accuracy: 0.01, "最近压力位 = 摆动高点")
        XCTAssertEqual(sup.first!.price, 90, accuracy: 0.01, "最近支撑位 = 摆动低点")
    }

    func testClusteringCountsTouches() {
        var spikes: [Int: (high: Double, low: Double, close: Double)] = [:]
        spikes[15] = (110.0, 100.5, 101)
        spikes[35] = (110.3, 100.5, 101)   // 与 110.0 相差 0.27%，应合并
        let bars = makeBars(count: 60, spikes: spikes)
        let levels = SupportResistance.levels(bars: bars)
        let res = levels.filter { $0.kind == .resistance }
        XCTAssertEqual(res.count, 1, "相近压力位应聚合成一簇")
        XCTAssertEqual(res.first!.touches, 2, "触摸次数应累计")
        XCTAssertEqual(res.first!.price, 110, accuracy: 0.01)
    }

    func testMaxPerSide() {
        var spikes: [Int: (high: Double, low: Double, close: Double)] = [:]
        spikes[12] = (112, 100.5, 101)
        spikes[24] = (108, 100.5, 101)
        spikes[36] = (120, 100.5, 101)
        spikes[20] = (99.5, 95, 98)
        spikes[44] = (99.5, 92, 98)
        spikes[30] = (99.5, 96, 98)
        let bars = makeBars(count: 70, spikes: spikes)
        let levels = SupportResistance.levels(bars: bars, maxPerSide: 2)
        XCTAssertEqual(levels.filter { $0.kind == .resistance }.count, 2)
        XCTAssertEqual(levels.filter { $0.kind == .support }.count, 2)
        // 每侧取最近：压力 108、112；支撑 96、95
        let resPrices = levels.filter { $0.kind == .resistance }.map(\.price)
        XCTAssertEqual(resPrices.first!, 108, accuracy: 0.01)
        let supPrices = levels.filter { $0.kind == .support }.map(\.price)
        XCTAssertEqual(supPrices.first!, 96, accuracy: 0.01)
    }

    func testEmptyAndShortInput() {
        XCTAssertTrue(SupportResistance.levels(bars: []).isEmpty)
        let short = makeBars(count: 5)
        XCTAssertTrue(SupportResistance.levels(bars: short).isEmpty, "数据不足时返回空")
    }
}
