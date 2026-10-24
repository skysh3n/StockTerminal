import XCTest
@testable import TradingCore

final class FormingKLineTests: XCTestCase {

    private func quote(
        last: Decimal, open: Decimal, high: Decimal, low: Decimal,
        volume: Int64 = 1_000_000, day: Date
    ) -> Quote {
        Quote(
            symbol: "SH600519",
            lastPrice: last, open: open, high: high, low: low,
            preClose: 100, bidPrice1: last, askPrice1: last,
            bidVolume1: 100, askVolume1: 100,
            volume: volume, turnover: Decimal(volume) * last,
            upperLimit: 110, lowerLimit: 90, timestamp: day
        )
    }

    func testDayBarUsesShanghaiStartOfDay() {
        let cal = MarketSession.shanghaiCalendar
        let ts = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 14, minute: 30))!
        let q = quote(last: 1335, open: 1311.84, high: 1343.88, low: 1310, day: ts)
        let bar = FormingKLine.dayBar(from: q)!
        XCTAssertEqual(cal.startOfDay(for: bar.timestamp), cal.startOfDay(for: ts))
        XCTAssertEqual(bar.close, Decimal(string: "1335")!)
        XCTAssertEqual(bar.open, Decimal(string: "1311.84")!)
        XCTAssertEqual(bar.high, Decimal(string: "1343.88")!)
        XCTAssertEqual(bar.low, Decimal(string: "1310")!)
        XCTAssertEqual(bar.volume, 1_000_000)
    }

    func testOverlayReplacesSameDay() {
        let cal = MarketSession.shanghaiCalendar
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 23))!
        let older = KLine(timestamp: day, open: 10, high: 11, low: 9, close: 10.5, volume: 100, turnover: 1000)
        let forming = FormingKLine.dayBar(from: quote(last: 12, open: 10, high: 12, low: 9.5, volume: 200, day: day.addingTimeInterval(10 * 3600)))!
        let out = FormingKLine.overlay([older], with: forming, timeFrame: .day)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].close, Decimal(12))
        XCTAssertEqual(out[0].volume, 200)
    }

    func testOverlayAppendsNewDay() {
        let cal = MarketSession.shanghaiCalendar
        let d1 = cal.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 10))!
        let prev = KLine(timestamp: d1, open: 10, high: 11, low: 9, close: 10.5, volume: 100, turnover: 1000)
        let forming = FormingKLine.dayBar(from: quote(last: 12, open: 11, high: 12, low: 10.8, day: d2))!
        let out = FormingKLine.overlay([prev], with: forming, timeFrame: .day)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.last?.close, Decimal(12))
    }

    func testSameBucketDayIgnoresIntradayTime() {
        let cal = MarketSession.shanghaiCalendar
        let a = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9, minute: 30))!
        let b = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15))!
        XCTAssertTrue(FormingKLine.sameBucket(a, b, timeFrame: .day))
        let c = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 15))!
        XCTAssertFalse(FormingKLine.sameBucket(a, c, timeFrame: .day))
    }
}
