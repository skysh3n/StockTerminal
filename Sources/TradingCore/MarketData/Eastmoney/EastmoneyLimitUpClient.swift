import Foundation

/// 涨停 / 逼近涨停池 + 选股榜兜底（clist 忽略 `fid`/`po` 时用）。
public struct EastmoneyLimitUpClient: Sendable {
    private let session: URLSession

    public enum SortColumn: String, Sendable {
        case changeRate = "CHANGE_RATE"
        case dealAmount = "DEAL_AMOUNT"
        case turnoverRate = "TURNOVERRATE"
        case amplitude = "AMPLITUDE"
    }

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
        try await xuanguPool(
            sort: .changeRate,
            filter: "(CHANGE_RATE%3E=9.8)",
            sortAsc: false,
            limit: limit,
            nearLimit: true
        )
    }

    /// 跌停 / 贴近跌停池。
    public func limitDownPool(limit: Int = 50) async throws -> [MarketRankItem] {
        try await xuanguPool(
            sort: .changeRate,
            filter: "(CHANGE_RATE%3C=-9.8)",
            sortAsc: true,
            limit: limit,
            nearLimit: true,
            down: true
        )
    }

    /// 跌幅榜兜底：涨跌幅升序且 ≤0（clist 忽略 po 时用）。
    public func losersPool(limit: Int = 40) async throws -> [MarketRankItem] {
        try await xuanguPool(
            sort: .changeRate,
            filter: "(CHANGE_RATE%3C=0)",
            sortAsc: true,
            limit: limit,
            nearLimit: false
        )
    }

    /// 按指标排序的全市场榜兜底（clist 忽略 fid 时用）。
    public func rankedPool(sort: SortColumn, limit: Int = 40) async throws -> [MarketRankItem] {
        try await xuanguPool(
            sort: sort,
            filter: "(NEW_PRICE%3E0)",
            sortAsc: false,
            limit: limit,
            nearLimit: false
        )
    }

    private func xuanguPool(
        sort: SortColumn,
        filter: String,
        sortAsc: Bool,
        limit: Int,
        nearLimit: Bool,
        down: Bool = false
    ) async throws -> [MarketRankItem] {
        let sr = sortAsc ? 1 : -1
        let ps = min(max(limit * 2, 20), 100)
        let sty =
            "SECURITY_CODE,SECURITY_NAME_ABBR,NEW_PRICE,CHANGE_RATE,DEAL_AMOUNT,TURNOVERRATE,AMPLITUDE,SECUCODE"
        let urlString =
            "https://data.eastmoney.com/dataapi/xuangu/list?st=\(sort.rawValue)&sr=\(sr)&ps=\(ps)&p=1&sty=\(sty)&filter=\(filter)"
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await session.data(from: url)
        return try Self.parse(data: data, limit: limit, nearLimit: nearLimit, down: down)
    }

    public static func parse(
        data: Data,
        limit: Int,
        nearLimit: Bool = true,
        down: Bool = false
    ) throws -> [MarketRankItem] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = json["result"] as? [String: Any],
            let rows = result["data"] as? [[String: Any]]
        else {
            throw ServiceError.backend("选股榜解析失败")
        }
        var out: [MarketRankItem] = []
        for row in rows {
            guard let code = row["SECURITY_CODE"] as? String, code.count == 6,
                  let name = row["SECURITY_NAME_ABBR"] as? String,
                  let exchange = exchange(from: row["SECUCODE"] as? String, code: code)
            else { continue }
            let pct = doubleValue(row["CHANGE_RATE"])
            let symbol = Symbol(code: code, exchange: exchange, name: name)
            if nearLimit {
                let threshold = limitThreshold(for: symbol)
                if down {
                    guard pct - 0.05 <= -threshold else { continue }
                } else {
                    guard pct + 0.05 >= threshold else { continue }
                }
            }
            let price = decimalValue(row["NEW_PRICE"])
            guard price > 0 else { continue }
            let turnover = decimalValue(row["DEAL_AMOUNT"])
            let turnoverRate = doubleValue(row["TURNOVERRATE"])
            let amplitude = doubleValue(row["AMPLITUDE"])
            out.append(MarketRankItem(
                symbol: symbol,
                lastPrice: price,
                changePercent: pct,
                change: price * Decimal(pct / 100.0),
                volumeLots: 0,
                turnover: turnover,
                turnoverRate: turnoverRate,
                amplitude: amplitude
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
