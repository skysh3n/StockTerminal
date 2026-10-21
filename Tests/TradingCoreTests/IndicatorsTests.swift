import XCTest
@testable import TradingCore

final class IndicatorsTests: XCTestCase {

    private let closes: [Double] = {
        var out: [Double] = []
        out.reserveCapacity(120)
        for i in 0..<120 {
            let wave = sin(Double(i) / 7.0) * 2.0
            let trend = Double(i) * 0.01
            out.append(10.0 + wave + trend)
        }
        return out
    }()
    private lazy var highs: [Double] = closes.map { $0 + 0.3 }
    private lazy var lows: [Double] = closes.map { $0 - 0.3 }

    func testSMAAlignment() {
        let out = Indicators.sma(closes, period: 5)
        XCTAssertEqual(out.count, closes.count)
        XCTAssertNil(out[3])
        XCTAssertNotNil(out[4])
        XCTAssertEqual(out[4]!, closes[0..<5].reduce(0, +) / 5, accuracy: 1e-9)
    }

    func testEMAConstantSeries() {
        let flat = [Double](repeating: 42, count: 30)
        let out = Indicators.ema(flat, period: 12)
        XCTAssertEqual(out.count, 30)
        XCTAssertNil(out[10])
        XCTAssertEqual(out[11]!, 42, accuracy: 1e-9)
        XCTAssertEqual(out[29]!, 42, accuracy: 1e-9)
    }

    func testEMAFollowsTrend() {
        let rising = (0..<60).map { Double($0) }
        let out = Indicators.ema(rising, period: 12)
        // 上升序列 EMA 落后于现值但同向递增
        XCTAssertLessThan(out.last!!, 59)
        XCTAssertGreaterThan(out.last!!, 40)
    }

    func testMACDShape() {
        let (dif, dea, hist) = Indicators.macd(closes)
        XCTAssertEqual(dif.count, closes.count)
        XCTAssertEqual(dea.count, closes.count)
        XCTAssertEqual(hist.count, closes.count)
        // 26 周期 EMA 未就绪前 DIF 为 nil
        XCTAssertNil(dif[10])
        XCTAssertNotNil(dif[30])
        // DEA 是 DIF 的平滑，更晚出现
        XCTAssertNil(dea[30])
        XCTAssertNotNil(dea[40])
        // hist = 2*(dif-dea) 对齐校验
        if let d = dif[60], let s = dea[60] {
            XCTAssertEqual(hist[60]!, (d - s) * 2, accuracy: 1e-9)
        }
    }

    func testKDJRange() {
        let (k, d, j) = Indicators.kdj(highs: highs, lows: lows, closes: closes)
        XCTAssertEqual(k.count, closes.count)
        XCTAssertNil(k[7])
        XCTAssertNotNil(k[8])
        for i in 8..<closes.count {
            XCTAssertGreaterThanOrEqual(k[i]!, 0)
            XCTAssertLessThanOrEqual(k[i]!, 100)
            XCTAssertGreaterThanOrEqual(d[i]!, 0)
            XCTAssertLessThanOrEqual(d[i]!, 100)
            // J = 3K - 2D
            XCTAssertEqual(j[i]!, 3 * k[i]! - 2 * d[i]!, accuracy: 1e-9)
        }
    }

    func testRSIRange() {
        for period in [6, 12, 24] {
            let out = Indicators.rsi(closes, period: period)
            XCTAssertEqual(out.count, closes.count)
            XCTAssertNil(out[period - 1])
            for v in out.compactMap({ $0 }) {
                XCTAssertGreaterThanOrEqual(v, 0)
                XCTAssertLessThanOrEqual(v, 100)
            }
        }
        // 单调上涨 → RSI 接近 100
        let rising = (0..<40).map { Double($0) + 1 }
        let out = Indicators.rsi(rising, period: 6)
        XCTAssertGreaterThan(out.last!!, 95)
    }

    func testBollBands() {
        let (upper, mid, lower) = Indicators.boll(closes)
        XCTAssertEqual(upper.count, closes.count)
        XCTAssertNil(upper[18])
        for i in 19..<closes.count {
            XCTAssertGreaterThanOrEqual(upper[i]!, mid[i]!)
            XCTAssertLessThanOrEqual(lower[i]!, mid[i]!)
        }
    }
}
