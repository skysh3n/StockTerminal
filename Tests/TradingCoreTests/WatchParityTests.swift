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

    func testRankEnforceOrderSeparatesTurnoverRateAndAmplitude() {
        // 涨幅序 A>B>C，但换手 C 最高、振幅 B 最高 → 三榜榜首应不同
        let a = MarketRankItem(
            symbol: Symbol(code: "600000", exchange: .sse, name: "A"),
            lastPrice: 10, changePercent: 9, change: 0.9, volumeLots: 1,
            turnover: 100, turnoverRate: 2, amplitude: 3
        )
        let b = MarketRankItem(
            symbol: Symbol(code: "000001", exchange: .szse, name: "B"),
            lastPrice: 10, changePercent: 5, change: 0.5, volumeLots: 1,
            turnover: 200, turnoverRate: 4, amplitude: 12
        )
        let c = MarketRankItem(
            symbol: Symbol(code: "300001", exchange: .szse, name: "C"),
            lastPrice: 10, changePercent: 1, change: 0.1, volumeLots: 1,
            turnover: 50, turnoverRate: 20, amplitude: 5
        )
        let pool = [a, b, c]
        let gainers = EastmoneyRankClient.enforceOrder(pool, kind: .gainers)
        let turnoverRate = EastmoneyRankClient.enforceOrder(pool, kind: .turnoverRate)
        let amplitude = EastmoneyRankClient.enforceOrder(pool, kind: .amplitude)
        XCTAssertEqual(gainers.first?.symbol.code, "600000")
        XCTAssertEqual(turnoverRate.first?.symbol.code, "300001")
        XCTAssertEqual(amplitude.first?.symbol.code, "000001")
        XCTAssertEqual(turnoverRate.map(\.turnoverRate), [20, 4, 2])
        XCTAssertEqual(amplitude.map(\.amplitude), [12, 5, 3])
    }

    func testClistIgnoredSortFidDetectsGainersBatch() {
        // 模拟 clist 忽略 fid=f8：按涨跌幅降序返回，换手率无序
        var batch: [MarketRankItem] = []
        for i in 0..<12 {
            let item = MarketRankItem(
                symbol: Symbol(code: String(format: "6000%02d", i), exchange: .sse, name: "S\(i)"),
                lastPrice: 10,
                changePercent: Double(12 - i),
                change: 1,
                volumeLots: 1,
                turnover: Decimal(100 - i),
                turnoverRate: Double((i * 7) % 11) + 0.5,
                amplitude: Double((i * 3) % 9) + 1
            )
            batch.append(item)
        }
        XCTAssertGreaterThan(EastmoneyRankClient.descendingPairScore(batch.map(\.changePercent)), 0.9)
        XCTAssertTrue(EastmoneyRankClient.clistIgnoredSortFid(batch, kind: .turnoverRate))
        XCTAssertTrue(EastmoneyRankClient.clistIgnoredSortFid(batch, kind: .amplitude))

        // 真正按换手降序的页不应触发
        let byTR = EastmoneyRankClient.enforceOrder(batch, kind: .turnoverRate)
        XCTAssertFalse(EastmoneyRankClient.clistIgnoredSortFid(byTR, kind: .turnoverRate))
    }

    func testXuanguParseIncludesTurnoverRateAndAmplitude() throws {
        let json = """
        {"result":{"data":[
          {"SECURITY_CODE":"300001","SECURITY_NAME_ABBR":"测A","NEW_PRICE":10.5,"CHANGE_RATE":2.1,
           "DEAL_AMOUNT":1.2e8,"TURNOVERRATE":15.5,"AMPLITUDE":8.2,"SECUCODE":"300001.SZ"},
          {"SECURITY_CODE":"600000","SECURITY_NAME_ABBR":"测B","NEW_PRICE":8.0,"CHANGE_RATE":-1.0,
           "DEAL_AMOUNT":9e7,"TURNOVERRATE":3.2,"AMPLITUDE":4.0,"SECUCODE":"600000.SH"}
        ]}}
        """.data(using: .utf8)!
        let items = try EastmoneyLimitUpClient.parse(data: json, limit: 10, nearLimit: false)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].turnoverRate, 15.5, accuracy: 0.01)
        XCTAssertEqual(items[0].amplitude, 8.2, accuracy: 0.01)
        XCTAssertEqual(items[1].symbol.fullCode, "SH600000")
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
        XCTAssertEqual(AShareIndices.all.count, 8)
        XCTAssertEqual(AShareIndices.shanghai.fullCode, "SH000001")
        XCTAssertEqual(AShareIndices.shenzhen.fullCode, "SZ399001")
        XCTAssertEqual(AShareIndices.chinext.fullCode, "SZ399006")
        XCTAssertEqual(AShareIndices.csi300.fullCode, "SH000300")
        XCTAssertEqual(AShareIndices.star50.fullCode, "SH000688")
        XCTAssertEqual(AShareIndices.bse50.fullCode, "BJ899050")
        XCTAssertFalse(StripGlobalIndices.items.isEmpty)
    }
}
