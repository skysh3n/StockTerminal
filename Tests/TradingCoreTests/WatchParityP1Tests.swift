import XCTest
@testable import TradingCore

final class WatchParityP1Tests: XCTestCase {

    func testSessionPhasesWeekday() {
        var cal = MarketSession.shanghaiCalendar
        // 2026-10-23 周五
        var c = DateComponents(calendar: cal, timeZone: cal.timeZone,
                               year: 2026, month: 10, day: 23, hour: 9, minute: 10)
        XCTAssertEqual(MarketSession.phase(at: cal.date(from: c)!), .preOpen)

        c.minute = 20
        XCTAssertEqual(MarketSession.phase(at: cal.date(from: c)!), .callAuction)

        c.hour = 10; c.minute = 0
        XCTAssertEqual(MarketSession.phase(at: cal.date(from: c)!), .continuousAM)
        XCTAssertTrue(MarketSession.phase(at: cal.date(from: c)!).isActiveTrading)

        c.hour = 12; c.minute = 0
        XCTAssertEqual(MarketSession.phase(at: cal.date(from: c)!), .lunch)

        c.hour = 14; c.minute = 0
        XCTAssertEqual(MarketSession.phase(at: cal.date(from: c)!), .continuousPM)

        c.hour = 16; c.minute = 0
        XCTAssertEqual(MarketSession.phase(at: cal.date(from: c)!), .afterClose)
    }

    func testSessionWeekend() {
        var cal = MarketSession.shanghaiCalendar
        let c = DateComponents(calendar: cal, timeZone: cal.timeZone,
                               year: 2026, month: 10, day: 24, hour: 10, minute: 0) // 周六
        XCTAssertEqual(MarketSession.phase(at: cal.date(from: c)!), .weekend)
        XCTAssertFalse(MarketSession.isOpen(at: cal.date(from: c)!))
    }

    func testSectorParse() throws {
        let json = """
        {"rc":0,"data":{"total":1,"diff":[
          {"f12":"BK0477","f14":"半导体","f3":2.5,"f104":40,"f105":10,"f128":"某芯片","f136":8.1}
        ]}}
        """.data(using: .utf8)!
        let boards = try EastmoneySectorClient.parseSectors(data: json, limit: 10)
        XCTAssertEqual(boards.count, 1)
        XCTAssertEqual(boards[0].code, "BK0477")
        XCTAssertEqual(boards[0].name, "半导体")
        XCTAssertEqual(boards[0].upCount, 40)
        XCTAssertEqual(boards[0].leadName, "某芯片")
    }

    func testSinaIndustryParse() throws {
        let text = #"var x={"new_blhy":"new_blhy,玻璃行业,19,14.7,0.15,1.05,100,200,sz300093,4.2,18.7,0.76,金刚光伏"};"#
        let data = text.data(using: .utf8)!
        let boards = try SinaSectorClient.parseIndustry(data: data, limit: 10)
        XCTAssertEqual(boards.count, 1)
        XCTAssertEqual(boards[0].name, "玻璃行业")
        XCTAssertEqual(boards[0].changePercent, 1.05, accuracy: 0.001)
        XCTAssertEqual(boards[0].leadName, "金刚光伏")
        XCTAssertEqual(boards[0].sourceNode, "new_blhy")
    }

    func testLimitUpParseAndThreshold() throws {
        let main = Symbol(code: "600000", exchange: .sse, name: "浦发")
        let gem = Symbol(code: "300001", exchange: .szse, name: "特锐德")
        XCTAssertEqual(EastmoneyLimitUpClient.limitThreshold(for: main), 9.75, accuracy: 0.01)
        XCTAssertEqual(EastmoneyLimitUpClient.limitThreshold(for: gem), 19.75, accuracy: 0.01)

        let json = """
        {"result":{"data":[
          {"SECURITY_CODE":"600000","SECURITY_NAME_ABBR":"浦发银行","NEW_PRICE":10.5,"CHANGE_RATE":10.0,"DEAL_AMOUNT":1e8,"SECUCODE":"600000.SH"},
          {"SECURITY_CODE":"300001","SECURITY_NAME_ABBR":"特锐德","NEW_PRICE":20,"CHANGE_RATE":5.0,"DEAL_AMOUNT":1e8,"SECUCODE":"300001.SZ"}
        ]}}
        """.data(using: .utf8)!
        let items = try EastmoneyLimitUpClient.parse(data: json, limit: 20)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].symbol.fullCode, "SH600000")
    }

    func testNewsParse() throws {
        let json = """
        {"code":"1","data":{"list":[
          {"code":"N1","title":"测试新闻","mediaName":"中证网","showTime":"2026-10-24 09:00:00","summary":"摘要","url":"http://stock.eastmoney.com/a/N1.html"}
        ]}}
        """.data(using: .utf8)!
        let items = try EastmoneyNewsClient.parse(data: json, limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "测试新闻")
        XCTAssertNotNil(items[0].url)
    }

    func testBillboardParse() throws {
        let json = """
        {"result":{"data":[
          {"SECURITY_CODE":"000001","SECURITY_NAME_ABBR":"平安银行","TRADE_DATE":"2026-10-23 00:00:00","CLOSE_PRICE":11.2,"CHANGE_RATE":2.1,"BILLBOARD_NET_AMT":1.5e7,"EXPLAIN":"机构买入"}
        ]}}
        """.data(using: .utf8)!
        let items = try EastmoneyBillboardClient.parse(data: json, limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].symbol.fullCode, "SZ000001")
        XCTAssertEqual(items[0].netAmount, Decimal(string: "15000000")!)
    }

    func testFundFlowParse() throws {
        let json = """
        {"rc":0,"data":{"klines":["2026-10-23 09:31,1000.0,-500.0,0,0,0"]}}
        """.data(using: .utf8)!
        let snap = try EastmoneyFundFlowClient.parse(data: json, symbol: "SH600519")
        XCTAssertEqual(snap?.mainNetInflow, 1000)
        XCTAssertEqual(snap?.retailNetInflow, -500)
    }
}
