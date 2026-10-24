import Foundation

/// 东财龙虎榜明细（datacenter-web 公开接口）。
public struct EastmoneyBillboardClient: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Referer": "https://data.eastmoney.com/stock/lhb.html",
        ]
        session = URLSession(configuration: config)
    }

    public func daily(limit: Int = 40, on date: Date = Date()) async throws -> [BillboardEntry] {
        let day = MarketSession.latestTradingDay(from: date)
        let first = try await fetch(day: day, limit: limit)
        if !first.isEmpty { return first }
        let cal = MarketSession.shanghaiCalendar
        guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { return first }
        return try await fetch(day: MarketSession.latestTradingDay(from: prev), limit: limit)
    }

    private func fetch(day: Date, limit: Int) async throws -> [BillboardEntry] {
        let cal = MarketSession.shanghaiCalendar
        let y = cal.component(.year, from: day)
        let m = cal.component(.month, from: day)
        let d = cal.component(.day, from: day)
        let dateStr = String(format: "%04d-%02d-%02d", y, m, d)
        let filter = "(TRADE_DATE%3D%27\(dateStr)%27)"
        let urlString =
            "https://datacenter-web.eastmoney.com/api/data/v1/get?sortColumns=BILLBOARD_NET_AMT&sortTypes=-1&pageSize=\(min(max(limit, 1), 50))&pageNumber=1&reportName=RPT_DAILYBILLBOARD_DETAILS&columns=SECURITY_CODE,SECURITY_NAME_ABBR,TRADE_DATE,CLOSE_PRICE,CHANGE_RATE,BILLBOARD_NET_AMT,EXPLAIN&filter=\(filter)"
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await session.data(from: url)
        return try Self.parse(data: data, limit: limit)
    }

    public static func parse(data: Data, limit: Int) throws -> [BillboardEntry] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = json["result"] as? [String: Any],
            let rows = result["data"] as? [[String: Any]]
        else {
            throw ServiceError.backend("龙虎榜解析失败")
        }
        // 东财 DETAILS 同一标的常因多席位/多理由重复出现；id 为 code-date，
        // 重复 Identifiable 会让 LazyVStack 中间留白。按净买额已排序，每码只留首条。
        var out: [BillboardEntry] = []
        var seen = Set<String>()
        for row in rows {
            guard let code = row["SECURITY_CODE"] as? String, code.count == 6,
                  let name = row["SECURITY_NAME_ABBR"] as? String,
                  let exchange = RealMarketDataService.exchange(forCode: code)
            else { continue }
            if seen.contains(code) { continue }
            seen.insert(code)
            let price = decimalValue(row["CLOSE_PRICE"])
            let pct = doubleValue(row["CHANGE_RATE"])
            let net = decimalValue(row["BILLBOARD_NET_AMT"])
            let explain = (row["EXPLAIN"] as? String) ?? ""
            var tradeDate = (row["TRADE_DATE"] as? String) ?? ""
            if tradeDate.count >= 10 { tradeDate = String(tradeDate.prefix(10)) }
            out.append(BillboardEntry(
                symbol: Symbol(code: code, exchange: exchange, name: name),
                closePrice: price,
                changePercent: pct,
                netAmount: net,
                explanation: explain,
                tradeDate: tradeDate
            ))
            if out.count >= limit { break }
        }
        return out
    }

    private static func doubleValue(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) ?? 0 }
        return 0
    }

    private static func decimalValue(_ any: Any?) -> Decimal {
        if let d = any as? Decimal { return d }
        if let n = any as? NSNumber { return Decimal(string: n.stringValue) ?? 0 }
        if let s = any as? String { return Decimal(string: s) ?? 0 }
        if let d = any as? Double { return Decimal(d) }
        return 0
    }
}
