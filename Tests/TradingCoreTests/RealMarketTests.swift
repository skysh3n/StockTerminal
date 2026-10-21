import XCTest
@testable import TradingCore

/// 真实数据适配层测试：代码映射为确定性测试；搜索为联网集成测试（离线自动跳过）
final class RealMarketTests: XCTestCase {

    func testExchangeMapping() {
        XCTAssertEqual(RealMarketDataService.exchange(forCode: "600519"), .sse)
        XCTAssertEqual(RealMarketDataService.exchange(forCode: "688256"), .sse)
        XCTAssertEqual(RealMarketDataService.exchange(forCode: "000001"), .szse)
        XCTAssertEqual(RealMarketDataService.exchange(forCode: "300750"), .szse)
        XCTAssertEqual(RealMarketDataService.exchange(forCode: "920002"), .bse)
        XCTAssertNil(RealMarketDataService.exchange(forCode: "ABCDEF"))
    }

    func testBSELimitRate() {
        let bse = Symbol(code: "830799", exchange: .bse, name: "测试北交所")
        XCTAssertEqual(bse.limitRate, Decimal(string: "0.3")!)
        let star = Symbol(code: "688256", exchange: .sse, name: "寒武纪")
        XCTAssertEqual(star.limitRate, Decimal(string: "0.2")!)
        let main = Symbol(code: "600519", exchange: .sse, name: "贵州茅台")
        XCTAssertEqual(main.limitRate, Decimal(string: "0.1")!)
    }

    func testTencentCodePrefix() {
        XCTAssertEqual(TencentMarketClient.code(for: Symbol(code: "600519", exchange: .sse, name: "贵州茅台")), "sh600519")
        XCTAssertEqual(TencentMarketClient.code(for: Symbol(code: "300750", exchange: .szse, name: "宁德时代")), "sz300750")
        XCTAssertEqual(TencentMarketClient.code(for: Symbol(code: "830799", exchange: .bse, name: "北交所")), "bj830799")
    }

    func testParseFullCode() {
        let sh = RealMarketDataService.parseFullCode("SH603688")
        XCTAssertEqual(sh?.code, "603688")
        XCTAssertEqual(sh?.exchange, .sse)
        XCTAssertEqual(RealMarketDataService.parseFullCode("SZ300750")?.exchange, .szse)
        XCTAssertEqual(RealMarketDataService.parseFullCode("BJ830799")?.exchange, .bse)
        XCTAssertNil(RealMarketDataService.parseFullCode("XX600000"))
        XCTAssertNil(RealMarketDataService.parseFullCode("SH60000"))
    }

    /// 搜索加入的新股票（不在初始 30 只池中）也必须能取到报价与历史（联网）
    func testDynamicSymbolQuotesAndHistory() async throws {
        let svc = RealMarketDataService(universe: MockSymbolUniverse.symbols)
        do {
            let quotes = try await svc.quotes(for: ["SH603688"])
            guard let q = quotes.first else { throw XCTSkip("离线或接口不可用") }
            XCTAssertGreaterThan(q.lastPrice, 0, "动态标的应能取到实时报价")
            let bars = try await svc.history(symbol: "SH603688", timeFrame: .day, count: 5)
            XCTAssertFalse(bars.isEmpty, "动态标的应能取到历史 K 线")
        } catch let e as XCTSkip {
            throw e
        } catch {
            throw XCTSkip("网络不可用：\(error)")
        }
    }

    /// 全市场搜索（联网）：能按代码搜到招行且解析为 A 股
    func testRealFullMarketSearch() async throws {
        let svc = RealMarketDataService(universe: MockSymbolUniverse.symbols)
        let results: [Symbol]
        do {
            results = try await svc.search(query: "600036", limit: 5)
        } catch {
            throw XCTSkip("网络不可用，跳过联网搜索测试：\(error)")
        }
        guard !results.isEmpty else {
            throw XCTSkip("搜索接口无结果（可能离线）")
        }
        XCTAssertTrue(
            results.contains { $0.code == "600036" && $0.exchange == .sse && $0.name == "招商银行" },
            "应能在全市场搜到招商银行，实际：\(results.map(\.fullCode))"
        )
    }

    /// 按名称搜索（联网）
    func testRealSearchByName() async throws {
        let svc = RealMarketDataService(universe: MockSymbolUniverse.symbols)
        let results: [Symbol]
        do {
            results = try await svc.search(query: "茅台", limit: 5)
        } catch {
            throw XCTSkip("网络不可用，跳过联网搜索测试：\(error)")
        }
        guard !results.isEmpty else {
            throw XCTSkip("搜索接口无结果（可能离线）")
        }
        XCTAssertTrue(results.contains { $0.code == "600519" })
    }
}
