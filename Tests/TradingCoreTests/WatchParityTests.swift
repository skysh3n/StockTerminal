import XCTest
@testable import TradingCore

final class WatchParityTests: XCTestCase {

    func testAlertEvaluatorAboveAndBelow() {
        var above = PriceAlert(
            symbol: "SH600519",
            name: "贵州茅台",
            direction: .above,
            threshold: Decimal(string: "1800")!
        )
        XCTAssertNotNil(AlertEvaluator.shouldTrigger(alert: above, lastPrice: Decimal(string: "1800")!, changePercent: 0))
        XCTAssertNil(AlertEvaluator.shouldTrigger(alert: above, lastPrice: Decimal(string: "1799.99")!, changePercent: 0))

        above.triggeredAt = Date()
        XCTAssertNil(AlertEvaluator.shouldTrigger(alert: above, lastPrice: Decimal(string: "1900")!, changePercent: 0))

        let below = PriceAlert(
            symbol: "SH600519",
            name: "贵州茅台",
            direction: .below,
            threshold: Decimal(string: "1700")!
        )
        XCTAssertNotNil(AlertEvaluator.shouldTrigger(alert: below, lastPrice: Decimal(string: "1700")!, changePercent: 0))
        XCTAssertNil(AlertEvaluator.shouldTrigger(alert: below, lastPrice: Decimal(string: "1700.01")!, changePercent: 0))
    }

    func testAlertEvaluatorDayChange() {
        let up = PriceAlert(
            symbol: "SH600000", name: "浦发",
            kind: .dayChangeUp, direction: .above, threshold: 3
        )
        XCTAssertNotNil(AlertEvaluator.shouldTrigger(alert: up, lastPrice: 10, changePercent: 3.0))
        XCTAssertNil(AlertEvaluator.shouldTrigger(alert: up, lastPrice: 10, changePercent: 2.9))

        let down = PriceAlert(
            symbol: "SH600000", name: "浦发",
            kind: .dayChangeDown, direction: .below, threshold: 3
        )
        XCTAssertNotNil(AlertEvaluator.shouldTrigger(alert: down, lastPrice: 10, changePercent: -3.0))
        XCTAssertNil(AlertEvaluator.shouldTrigger(alert: down, lastPrice: 10, changePercent: -2.9))
    }

    func testAlertEvaluatorDisabled() {
        let alert = PriceAlert(
            symbol: "SZ000001",
            name: "平安银行",
            direction: .above,
            threshold: 10,
            enabled: false
        )
        XCTAssertNil(AlertEvaluator.shouldTrigger(alert: alert, lastPrice: 99, changePercent: 0))
    }

    func testRankClientParse() throws {
        let json = """
        {"rc":0,"data":{"total":2,"diff":[
          {"f2":32.08,"f3":10.5,"f4":3.05,"f5":1000,"f6":1234567.0,"f7":2.1,"f8":1.5,"f12":"600519","f13":1,"f14":"贵州茅台"},
          {"f2":11.2,"f3":-3.2,"f4":-0.37,"f5":2000,"f6":999.0,"f7":4.0,"f8":3.2,"f12":"000001","f13":0,"f14":"平安银行"}
        ]}}
        """.data(using: .utf8)!
        let items = try EastmoneyRankClient.parse(data: json, limit: 10)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].symbol.fullCode, "SH600519")
        XCTAssertEqual(items[0].changePercent, 10.5, accuracy: 0.001)
        XCTAssertEqual(items[1].symbol.fullCode, "SZ000001")
        XCTAssertEqual(items[1].turnover, Decimal(string: "999")!)
        XCTAssertEqual(items[1].amplitude, 4.0, accuracy: 0.001)
    }

    func testRankEnforceOrderSeparatesGainersLosers() throws {
        let a = MarketRankItem(
            symbol: Symbol(code: "600000", exchange: .sse, name: "A"),
            lastPrice: 10, changePercent: 5, change: 0.5, volumeLots: 1, turnover: 1
        )
        let b = MarketRankItem(
            symbol: Symbol(code: "000001", exchange: .szse, name: "B"),
            lastPrice: 10, changePercent: -4, change: -0.4, volumeLots: 1, turnover: 1
        )
        let c = MarketRankItem(
            symbol: Symbol(code: "300001", exchange: .szse, name: "C"),
            lastPrice: 10, changePercent: 9, change: 0.9, volumeLots: 1, turnover: 1
        )
        let gainers = EastmoneyRankClient.enforceOrder([a, b, c], kind: .gainers)
        let losers = EastmoneyRankClient.enforceOrder([a, b, c], kind: .losers)
        XCTAssertEqual(gainers.map(\.changePercent), [9, 5, -4])
        XCTAssertEqual(losers.map(\.changePercent), [-4, 5, 9])
        XCTAssertNotEqual(gainers.first?.symbol.fullCode, losers.first?.symbol.fullCode)
    }

    func testNoticeClientParse() throws {
        let json = """
        {"data":{"list":[
          {"art_code":"AN1","title_ch":"测试公告","notice_date":"2026-10-15 00:00:00"},
          {"art_code":"AN2","title":"另一条","notice_date":"2026-10-01 00:00:00"}
        ]}}
        """.data(using: .utf8)!
        let items = try EastmoneyNoticeClient.parse(data: json, code: "600519", limit: 10)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "测试公告")
        XCTAssertEqual(items[0].noticeDate, "2026-10-15")
        XCTAssertEqual(items[0].url?.absoluteString, "https://data.eastmoney.com/notices/detail/600519/AN1.html")
    }

    func testAShareIndicesCodes() {
        XCTAssertEqual(AShareIndices.all.count, 3)
        XCTAssertEqual(AShareIndices.shanghai.fullCode, "SH000001")
        XCTAssertEqual(AShareIndices.shenzhen.fullCode, "SZ399001")
        XCTAssertEqual(AShareIndices.chinext.fullCode, "SZ399006")
    }
}
