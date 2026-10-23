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

    /// `v_usDJI="200~道琼斯~.DJI~最新~昨收~...";`：3 最新、4 昨收、31 涨跌、32 涨跌幅、33 最高、34 最低。
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
                high: Double(f[33]).flatMap { $0 > 0 ? $0 : nil },
                low: Double(f[34]).flatMap { $0 > 0 ? $0 : nil }
            )
        }
    }

    /// `var hq_str_znb_NKY="日经225,最新,涨跌,涨跌幅,...,开盘,昨收,最高,最低,...";`
    /// 部分指数只有前 6 个字段，没有高低价。
    static func parseSina(_ text: String, ids: [String: String]) -> [GlobalIndexQuote] {
        assignments(in: text, prefix: "var hq_str_").compactMap { code, body in
            guard let id = ids[code] else { return nil }
            let f = body.components(separatedBy: ",")
            guard f.count >= 4, let last = Double(f[1]), last > 0 else { return nil }
            let full = f.count >= 12
            return GlobalIndexQuote(
                id: id, last: last,
                change: Double(f[2]) ?? 0,
                changePercent: Double(f[3]) ?? 0,
                high: full ? Double(f[10]).flatMap { $0 > 0 ? $0 : nil } : nil,
                low: full ? Double(f[11]).flatMap { $0 > 0 ? $0 : nil } : nil
            )
        }
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
