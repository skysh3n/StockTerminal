import XCTest
@testable import TradingCore

final class GlobalIndexTests: XCTestCase {

    func testParseTencentIndices() {
        let text = """
        v_usDJI="200~道琼斯~.DJI~52867.98~52856.09~52788.41~506198387~0~0~52559.33~0~0~0~0~0~0~0~0~0~52943.94~0~0~0~0~0~0~0~0~0~~2026-10-22 16:31:52~11.89~0.02~52927.88~52508.38~USD~506198387~26713570291311~~~~~~0.79";
        v_hkHSI="100~恒生指数~HSI~23093.370~22934.680~23027.980~24978359.0343~0~0~23093.370~0~0~0~0~0~0~0~0~0~23093.370~0~0~0~0~0~0~0~0~0~0.0~2026/10/23 17:52:07~158.690~0.69~23231.630~22803.770~23093.370";
        v_sh000001="1~上证指数~000001~3690.48~3658.03~3623.57~552842912~0~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~~20261023161500~32.45~0.89~3691.40~3574.27~3690.48";
        """
        let ids = ["usDJI": "usDJI", "hkHSI": "hkHSI", "sh000001": "sh000001"]
        let quotes = Dictionary(uniqueKeysWithValues: GlobalIndexClient.parseTencent(text, ids: ids).map { ($0.id, $0) })
        XCTAssertEqual(quotes.count, 3)
        XCTAssertEqual(quotes["usDJI"]?.last, 52867.98)
        XCTAssertEqual(quotes["usDJI"]?.change, 11.89)
        XCTAssertEqual(quotes["hkHSI"]?.changePercent, 0.69)
        XCTAssertEqual(quotes["hkHSI"]?.high, 23231.63)
        XCTAssertEqual(quotes["sh000001"]?.low, 3574.27)
        XCTAssertEqual(quotes["usDJI"]?.preClose, 52856.09)
        XCTAssertEqual(quotes["usDJI"]?.open, 52788.41)
    }

    func testParseDailyHistory() {
        let tencent = Data(#"{"code":0,"data":{"us.DJI":{"day":[["2026-10-21","52652.850","52856.090","52860.110","52392.280","359385262.000"],["2026-10-22","52788.410","52867.980","52927.880","52508.380","506198387.000"]]}}}"#.utf8)
        let t = GlobalIndexClient.parseTencentDaily(tencent, code: "us.DJI")
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(t.last?.close, 52867.98)
        XCTAssertEqual(t.last?.high, 52927.88)

        let sina = Data(#"{"code":0,"message":"","result":{"data":[{"d":"2026-10-22","v":"0","c":"62907.84","o":"64539.36","l":"62907.84","h":"64866.44"},{"d":"2026-10-23","v":"0","c":"62693.1602","o":"62667.0508","l":"61462.6094","h":"62786.8906"}]}}"#.utf8)
        let s = GlobalIndexClient.parseSinaDaily(sina)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.first?.open, 64539.36)
        XCTAssertLessThan(s[0].date, s[1].date)
    }

    func testHistorySourceMapping() {
        func history(_ id: String) -> GlobalIndex.HistorySource? {
            GlobalIndex.catalog.first { $0.id == id }?.history
        }
        XCTAssertEqual(history("usDJI"), .tencent("us.DJI"))
        XCTAssertEqual(history("hkHSI"), .tencent("hkHSI"))
        XCTAssertEqual(history("NKY"), .sina("NKY"))
        XCTAssertNil(history("SMI"))
    }

    func testParseSinaIndices() {
        let text = """
        var hq_str_znb_NKY="日经225,62692.9400,-214.90,-0.34,2:12 AM,1759126320,2026-10-23,14:30:01,62667.0500,62907.8398,62786.8900,61462.6100,0";
        var hq_str_znb_SMI="瑞士市场指数,11929.80,54.00,0.45,9/26/2025,1758859200";
        var hq_str_znb_RTSI="";
        """
        let ids = ["znb_NKY": "NKY", "znb_SMI": "SMI", "znb_RTSI": "RTSI"]
        let quotes = Dictionary(uniqueKeysWithValues: GlobalIndexClient.parseSina(text, ids: ids).map { ($0.id, $0) })
        XCTAssertEqual(quotes.count, 2, "空报价应被跳过")
        XCTAssertEqual(quotes["NKY"]?.last, 62692.94)
        XCTAssertEqual(quotes["NKY"]?.changePercent, -0.34)
        XCTAssertEqual(quotes["NKY"]?.high, 62786.89)
        XCTAssertEqual(quotes["SMI"]?.change, 54.00)
        XCTAssertNil(quotes["SMI"]?.high, "短格式没有高低价")
    }

    func testTradingSessions() throws {
        let hsi = try XCTUnwrap(GlobalIndex.catalog.first { $0.id == "hkHSI" })
        let dji = try XCTUnwrap(GlobalIndex.catalog.first { $0.id == "usDJI" })
        let f = ISO8601DateFormatter()
        // 2026-10-23 周五 10:00 香港 = 前一天 22:00 纽约
        let hkMorning = try XCTUnwrap(f.date(from: "2026-10-23T02:00:00Z"))
        XCTAssertTrue(hsi.isTrading(at: hkMorning))
        XCTAssertFalse(dji.isTrading(at: hkMorning))
        // 午休
        XCTAssertFalse(hsi.isTrading(at: try XCTUnwrap(f.date(from: "2026-10-23T04:30:00Z"))))
        // 周五 10:00 纽约
        XCTAssertTrue(dji.isTrading(at: try XCTUnwrap(f.date(from: "2026-10-23T14:00:00Z"))))
        // 周六
        XCTAssertFalse(hsi.isTrading(at: try XCTUnwrap(f.date(from: "2026-10-24T02:00:00Z"))))
    }

    func testCatalogIDsUnique() {
        let ids = GlobalIndex.catalog.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        for region in GlobalIndex.Region.allCases {
            XCTAssertTrue(GlobalIndex.catalog.contains { $0.region == region })
        }
    }

    /// 联网：两个源都应能取到报价（离线自动跳过）
    func testLiveQuotes() async throws {
        let quotes = await GlobalIndexClient().quotes(for: GlobalIndex.catalog)
        guard !quotes.isEmpty else { throw XCTSkip("离线或接口不可用") }
        XCTAssertNotNil(quotes["usDJI"])
        XCTAssertNotNil(quotes["NKY"])

        let client = GlobalIndexClient()
        for id in ["usDJI", "NKY"] {
            let index = try XCTUnwrap(GlobalIndex.catalog.first { $0.id == id })
            let bars = await client.dailyHistory(for: index, count: 30)
            XCTAssertFalse(bars.isEmpty, "\(id) 应能取到日线")
        }
    }
}
