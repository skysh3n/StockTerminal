import Foundation

/// 全球股指快照：A 股 / 港股 / 美股走腾讯，其余走新浪全球指数（均为 GB18030 文本）。
public struct GlobalIndexClient: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        ]
        session = URLSession(configuration: config)
    }

    /// 两个源并发请求；单个源失败只影响它自己的指数。
    public func quotes(for indices: [GlobalIndex]) async -> [String: GlobalIndexQuote] {
        var tencent: [String: String] = [:]
        var sina: [String: String] = [:]
        for index in indices {
            switch index.source {
            case .tencent(let code): tencent[code] = index.id
            case .sina(let code): sina[code] = index.id
            }
        }

        async let t = fetch(
            "https://qt.gtimg.cn/q=" + tencent.keys.sorted().joined(separator: ","),
            referer: "https://gu.qq.com/",
            skip: tencent.isEmpty
        )
        async let s = fetch(
            "https://hq.sinajs.cn/list=" + sina.keys.sorted().joined(separator: ","),
            referer: "https://finance.sina.com.cn/",
            skip: sina.isEmpty
        )
        let (tText, sText) = await (t, s)

        var out: [String: GlobalIndexQuote] = [:]
        if let tText {
            for q in Self.parseTencent(tText, ids: tencent) { out[q.id] = q }
        }
        if let sText {
            for q in Self.parseSina(sText, ids: sina) { out[q.id] = q }
        }
        return out
    }

    private func fetch(_ urlString: String, referer: String, skip: Bool) async -> String? {
        guard !skip, let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return GB18030.decode(data)
    }

    /// `v_usDJI="200~道琼斯~.DJI~最新~昨收~今开~...";`：3 最新、4 昨收、5 今开、31 涨跌、32 涨跌幅、33 最高、34 最低。
    static func parseTencent(_ text: String, ids: [String: String]) -> [GlobalIndexQuote] {
        assignments(in: text, prefix: "v_").compactMap { code, body in
            guard let id = ids[code] else { return nil }
            let f = body.components(separatedBy: "~")
            guard f.count > 34, let last = Double(f[3]), last > 0 else { return nil }
            let pre = Double(f[4]) ?? 0
            let change = Double(f[31]) ?? (pre > 0 ? last - pre : 0)
            let pct = Double(f[32]) ?? (pre > 0 ? change / pre * 100 : 0)
            return GlobalIndexQuote(
                id: id, last: last, change: change, changePercent: pct,
                open: positive(f[5]),
                preClose: pre > 0 ? pre : nil,
                high: positive(f[33]),
                low: positive(f[34])
            )
        }
    }

    /// `var hq_str_znb_NKY="日经225,最新,涨跌,涨跌幅,...,开盘,昨收,最高,最低,...";`
    /// 部分指数只有前 6 个字段，没有开盘与高低价，昨收由最新价减涨跌推出。
    static func parseSina(_ text: String, ids: [String: String]) -> [GlobalIndexQuote] {
        assignments(in: text, prefix: "var hq_str_").compactMap { code, body in
            guard let id = ids[code] else { return nil }
            let f = body.components(separatedBy: ",")
            guard f.count >= 4, let last = Double(f[1]), last > 0 else { return nil }
            let full = f.count >= 12
            let change = Double(f[2]) ?? 0
            return GlobalIndexQuote(
                id: id, last: last,
                change: change,
                changePercent: Double(f[3]) ?? 0,
                open: full ? positive(f[8]) : nil,
                preClose: full ? positive(f[9]) : (last - change > 0 ? last - change : nil),
                high: full ? positive(f[10]) : nil,
                low: full ? positive(f[11]) : nil
            )
        }
    }

    private static func positive(_ s: String) -> Double? {
        Double(s).flatMap { $0 > 0 ? $0 : nil }
    }

    // MARK: - 日线

    /// 最近 `count` 根日线，按日期升序。无历史源或请求失败返回空数组。
    public func dailyHistory(for index: GlobalIndex, count: Int = 800) async -> [GlobalIndexBar] {
        switch index.history {
        case .tencent(let code):
            let url = "https://ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(code),day,,,\(count),qfq"
            guard let data = await fetchData(url, referer: "https://gu.qq.com/") else { return [] }
            return Array(Self.parseTencentDaily(data, code: code).suffix(count))
        case .sina(let symbol):
            let url = "https://gi.finance.sina.com.cn/hq/daily?symbol=\(symbol)&num=\(count)"
            guard let data = await fetchData(url, referer: "https://finance.sina.com.cn/") else { return [] }
            return Array(Self.parseSinaDaily(data).suffix(count))
        case nil:
            return []
        }
    }

    private func fetchData(_ urlString: String, referer: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        return try? await session.data(for: request).0
    }

    /// `data.<code>.day` 或 `qfqday`：`[日期, 开, 收, 高, 低, 量]`
    static func parseTencentDaily(_ data: Data, code: String) -> [GlobalIndexBar] {
        guard
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let root = json["data"] as? [String: Any],
            let node = root[code] as? [String: Any],
            let rows = (node["qfqday"] ?? node["day"]) as? [[Any]]
        else { return [] }
        return rows.compactMap { row in
            guard row.count >= 5,
                  let date = dayDate("\(row[0])"),
                  let o = Double("\(row[1])"), let c = Double("\(row[2])"),
                  let h = Double("\(row[3])"), let l = Double("\(row[4])"),
                  c > 0
            else { return nil }
            return GlobalIndexBar(date: date, open: o, high: h, low: l, close: c)
        }
    }

    /// `result.data`：`[{d, o, h, l, c, v}]`，升序。
    static func parseSinaDaily(_ data: Data) -> [GlobalIndexBar] {
        guard
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let result = json["result"] as? [String: Any],
            let rows = result["data"] as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row in
            func num(_ k: String) -> Double? { (row[k] as? String).flatMap(Double.init) ?? (row[k] as? Double) }
            guard let d = row["d"] as? String, let date = dayDate(d),
                  let o = num("o"), let h = num("h"), let l = num("l"), let c = num("c"), c > 0
            else { return nil }
            return GlobalIndexBar(date: date, open: o, high: h, low: l, close: c)
        }
    }

    private static func dayDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    /// 拆出 `<prefix>code="body"` 形式的赋值语句。
    private static func assignments(in text: String, prefix: String) -> [(String, String)] {
        text.split(whereSeparator: { $0 == ";" || $0 == "\n" }).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(prefix), let eq = line.firstIndex(of: "=") else { return nil }
            let code = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<eq])
            var body = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("\"") { body.removeFirst() }
            if body.hasSuffix("\"") { body.removeLast() }
            guard !body.isEmpty else { return nil }
            return (code, body)
        }
    }
}
