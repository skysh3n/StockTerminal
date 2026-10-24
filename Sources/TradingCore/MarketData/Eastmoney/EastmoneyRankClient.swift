import Foundation

/// 东方财富全市场榜单（涨跌幅 / 成交额 / 换手 / 振幅），公开 clist 接口。
public struct EastmoneyRankClient: Sendable {
    private let session: URLSession
    private let xuangu = EastmoneyLimitUpClient()

    /// 东财页面常用 token；缺省时部分节点会忽略 `po`/`fid`，导致多榜同批股票。
    public static let ut = "fa5fd1943c7b386f172d6893dbfba10b"

    public init() {
        session = EastmoneyHTTP.makeSession(referer: "https://quote.eastmoney.com/")
    }

    /// A 股过滤串（沪深京主板/创业/科创）。
    public static let aShareFS = "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23"

    public func ranking(kind: MarketRankKind, limit: Int = 40) async throws -> [MarketRankItem] {
        // fid：f3 涨跌幅 / f6 成交额 / f8 换手率 / f7 振幅
        // po：0 升序、1 降序（跌幅榜必须升序，否则会与涨幅榜同批股票）
        let (fid, po): (String, Int) = {
            switch kind {
            case .gainers: return ("f3", 1)
            case .losers: return ("f3", 0)
            case .turnover: return ("f6", 1)
            case .turnoverRate: return ("f8", 1)
            case .amplitude: return ("f7", 1)
            }
        }()
        let pz = min(max(limit, 1), 50)
        let fields = "f12,f13,f14,f2,f3,f4,f5,f6,f7,f8"
        // `_` 防 CDN 把不同 fid 并成同一缓存键
        let bust = Int(Date().timeIntervalSince1970 * 1000)
        let query =
            "pn=1&pz=\(pz)&po=\(po)&np=1&ut=\(Self.ut)&fltt=2&invt=2&fid=\(fid)&fs=\(Self.aShareFS)&fields=\(fields)&_=\(bust)"

        var items: [MarketRankItem] = []
        var usedClist = false
        do {
            let data = try await EastmoneyHTTP.fetchClist(session: session, query: query)
            items = try Self.parse(data: data, limit: pz)
            usedClist = true
        } catch {
            // clist 挂了直接走选股兜底
            items = []
        }

        let needsFallback: Bool = {
            if items.isEmpty { return true }
            if kind == .losers {
                let upCount = items.filter { $0.changePercent >= 0 }.count
                return upCount * 2 >= items.count
            }
            // 换手 / 振幅 / 成交额：clist 常忽略 fid，仍返回涨幅序同批股票
            if kind == .turnover || kind == .turnoverRate || kind == .amplitude {
                return usedClist && Self.clistIgnoredSortFid(items, kind: kind)
            }
            return false
        }()

        if needsFallback, let sort = Self.xuanguSort(for: kind) {
            let fallback: [MarketRankItem]
            if kind == .losers {
                fallback = (try? await xuangu.losersPool(limit: pz)) ?? []
            } else {
                fallback = (try? await xuangu.rankedPool(sort: sort, limit: pz)) ?? []
            }
            if !fallback.isEmpty {
                items = fallback
            }
        }

        return Self.enforceOrder(items, kind: kind)
    }

    private static func xuanguSort(for kind: MarketRankKind) -> EastmoneyLimitUpClient.SortColumn? {
        switch kind {
        case .gainers: return .changeRate
        case .losers: return .changeRate
        case .turnover: return .dealAmount
        case .turnoverRate: return .turnoverRate
        case .amplitude: return .amplitude
        }
    }

    /// 判断 clist 是否忽略了 `fid`：原始行更像按涨跌幅降序，而不是按目标指标降序。
    public static func clistIgnoredSortFid(_ items: [MarketRankItem], kind: MarketRankKind) -> Bool {
        guard items.count >= 8 else { return false }
        let metricValues: [Double] = {
            switch kind {
            case .turnover: return items.map { ($0.turnover as NSDecimalNumber).doubleValue }
            case .turnoverRate: return items.map(\.turnoverRate)
            case .amplitude: return items.map(\.amplitude)
            case .gainers, .losers: return items.map(\.changePercent)
            }
        }()
        // 目标指标几乎全 0 → 字段没回来，不可信
        if metricValues.filter({ $0 > 0 }).count < items.count / 3 { return true }

        let changes = items.map(\.changePercent)
        let changeScore = descendingPairScore(changes)
        let metricScore = descendingPairScore(metricValues)

        let maxMetric = metricValues.max() ?? 0
        let maxChange = changes.max() ?? 0
        let firstIsChangeLeader = changes[0] + 1e-9 >= maxChange * 0.98
        let firstIsMetricLeader = metricValues[0] + 1e-9 >= maxMetric * 0.98
        // 榜首是涨幅王却不是指标王 → 典型忽略 fid（仍按 f3 排序）
        if firstIsChangeLeader && !firstIsMetricLeader { return true }

        // 涨跌幅序很整齐，目标指标序明显更乱
        return changeScore >= 0.85 && metricScore < 0.7
    }

    /// 相邻对满足降序的比例（1 = 严格降序）。
    public static func descendingPairScore(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 1 }
        var ok = 0
        for i in 0..<(values.count - 1) {
            if values[i] + 1e-9 >= values[i + 1] { ok += 1 }
        }
        return Double(ok) / Double(values.count - 1)
    }

    /// 按榜单语义强制排序（并在跌幅榜误拿到涨幅批时尽量纠正观感：升序后取最负的在前）。
    public static func enforceOrder(_ items: [MarketRankItem], kind: MarketRankKind) -> [MarketRankItem] {
        var out = items
        switch kind {
        case .gainers:
            out.sort { $0.changePercent > $1.changePercent }
        case .losers:
            out.sort { $0.changePercent < $1.changePercent }
        case .turnover:
            out.sort { $0.turnover > $1.turnover }
        case .turnoverRate:
            out.sort { $0.turnoverRate > $1.turnoverRate }
        case .amplitude:
            out.sort { $0.amplitude > $1.amplitude }
        }
        return out
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
            let amplitude = doubleValue(row["f7"])
            let turnoverRate = doubleValue(row["f8"])
            out.append(MarketRankItem(
                symbol: Symbol(code: code, exchange: exchange, name: name),
                lastPrice: price,
                changePercent: pct,
                change: change,
                volumeLots: lots,
                turnover: turnover,
                turnoverRate: turnoverRate,
                amplitude: amplitude
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
