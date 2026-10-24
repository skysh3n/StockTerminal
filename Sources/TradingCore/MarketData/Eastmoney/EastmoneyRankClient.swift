import Foundation

/// 东方财富全市场榜单（涨跌幅 / 成交额），公开 clist 接口。
public struct EastmoneyRankClient: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            "Referer": "https://quote.eastmoney.com/",
        ]
        session = URLSession(configuration: config)
    }

    /// A 股过滤串（沪深京主板/创业/科创）。
    public static let aShareFS = "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23"

    public func ranking(kind: MarketRankKind, limit: Int = 40) async throws -> [MarketRankItem] {
        let (fid, po): (String, Int) = {
            switch kind {
            case .gainers: return ("f3", 1)
            case .losers: return ("f3", 0)
            case .turnover: return ("f6", 1)
            }
        }()
        let pz = min(max(limit, 1), 50)
        let fields = "f12,f13,f14,f2,f3,f4,f5,f6"
        let urlString =
            "https://push2.eastmoney.com/api/qt/clist/get?pn=1&pz=\(pz)&po=\(po)&np=1&fltt=2&invt=2&fid=\(fid)&fs=\(Self.aShareFS)&fields=\(fields)"
        guard let url = URL(string: urlString) else { return [] }

        let (data, _) = try await session.data(from: url)
        return try Self.parse(data: data, limit: pz)
    }

    /// 解析 clist JSON；暴露给单测。
    public static func parse(data: Data, limit: Int) throws -> [MarketRankItem] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = json["data"] as? [String: Any],
            let rows = dataObj["diff"] as? [[String: Any]]
        else {
            throw ServiceError.backend("榜单解析失败")
        }

        var out: [MarketRankItem] = []
        out.reserveCapacity(min(rows.count, limit))
        for row in rows {
            guard let code = stringValue(row["f12"]),
                  code.count == 6, code.allSatisfy(\.isNumber),
                  let name = stringValue(row["f14"]), !name.isEmpty,
                  let exchange = exchange(market: intValue(row["f13"]), code: code)
            else { continue }
            let price = decimalValue(row["f2"])
            guard price > 0 else { continue }
            let pct = doubleValue(row["f3"])
            let change = decimalValue(row["f4"])
            let lots = Int64(doubleValue(row["f5"]).rounded())
            let turnover = decimalValue(row["f6"])
            out.append(MarketRankItem(
                symbol: Symbol(code: code, exchange: exchange, name: name),
                lastPrice: price,
                changePercent: pct,
                change: change,
                volumeLots: lots,
                turnover: turnover
            ))
            if out.count >= limit { break }
        }
        return out
    }

    /// f13：0 深 / 1 沪；北交所以代码前缀兜底。
    static func exchange(market: Int?, code: String) -> Exchange? {
        if let market {
            switch market {
            case 1: return .sse
            case 0: return .szse
            default: break
            }
        }
        return RealMarketDataService.exchange(forCode: code)
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
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
