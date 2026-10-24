import Foundation

/// 涨停 / 逼近涨停池（公开选股接口近似；非官方「涨停池」专页）。
public struct EastmoneyLimitUpClient: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Referer": "https://data.eastmoney.com/",
        ]
        session = URLSession(configuration: config)
    }

    /// 拉取涨跌幅 ≥ 9.8% 的标的，再按各自涨停幅度过滤「触及/贴近涨停」。
    public func limitUpPool(limit: Int = 50) async throws -> [MarketRankItem] {
        let urlString =
            "https://data.eastmoney.com/dataapi/xuangu/list?st=CHANGE_RATE&sr=-1&ps=\(min(max(limit * 2, 20), 100))&p=1&sty=SECURITY_CODE,SECURITY_NAME_ABBR,NEW_PRICE,CHANGE_RATE,DEAL_AMOUNT,SECUCODE&filter=(CHANGE_RATE%3E=9.8)"
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await session.data(from: url)
        return try Self.parse(data: data, limit: limit)
    }

    public static func parse(data: Data, limit: Int) throws -> [MarketRankItem] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = json["result"] as? [String: Any],
            let rows = result["data"] as? [[String: Any]]
        else {
            throw ServiceError.backend("涨停池解析失败")
        }
        var out: [MarketRankItem] = []
        for row in rows {
            guard let code = row["SECURITY_CODE"] as? String, code.count == 6,
                  let name = row["SECURITY_NAME_ABBR"] as? String,
                  let exchange = exchange(from: row["SECUCODE"] as? String, code: code)
            else { continue }
            let pct = doubleValue(row["CHANGE_RATE"])
            let symbol = Symbol(code: code, exchange: exchange, name: name)
            // 贴近各自板涨停：主板 ≥9.8，创/科 ≥19.5，北交 ≥29.5
            let threshold = limitThreshold(for: symbol)
            guard pct + 0.05 >= threshold else { continue }
            let price = decimalValue(row["NEW_PRICE"])
            guard price > 0 else { continue }
            let turnover = decimalValue(row["DEAL_AMOUNT"])
            out.append(MarketRankItem(
                symbol: symbol,
                lastPrice: price,
                changePercent: pct,
                change: price * Decimal(pct / 100.0),
                volumeLots: 0,
                turnover: turnover
            ))
            if out.count >= limit { break }
        }
        return out
    }

    /// 判定「算涨停池」的涨跌幅下限（百分点）。
    public static func limitThreshold(for symbol: Symbol) -> Double {
        let rate = symbol.limitRate.doubleValue * 100
        // 略低于名义涨停，兼容四舍五入与触板未封死
        return max(rate - 0.25, 9.5)
    }

    private static func exchange(from secu: String?, code: String) -> Exchange? {
        if let secu {
            if secu.hasSuffix(".SH") { return .sse }
            if secu.hasSuffix(".SZ") { return .szse }
            if secu.hasSuffix(".BJ") { return .bse }
        }
        return RealMarketDataService.exchange(forCode: code)
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
