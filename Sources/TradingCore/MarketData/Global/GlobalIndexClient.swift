import Foundation

/// 全球股指：快照 + 分时 / 日 / 周 / 月线。
public struct GlobalIndexClient: Sendable {
    public enum KLinePeriod: String, Sendable {
        case day, week, month
    }

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

    // MARK: - 分时

    /// 当日分时。仅腾讯源（A/港/美）有数据；新浪外盘返回空。
    public func minuteHistory(for index: GlobalIndex) async -> GlobalMinuteSeries {
        guard let code = index.tencentMinuteCode else {
            return GlobalMinuteSeries(bars: [], preClose: nil)
        }
        let path = index.isUSTencent
            ? "https://web.ifzq.gtimg.cn/appstock/app/UsMinute/query?code=\(code)"
            : "https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=\(code)"
        guard let data = await fetchData(path, referer: "https://gu.qq.com/") else {
            return GlobalMinuteSeries(bars: [], preClose: nil)
        }
        return Self.parseTencentMinute(data, code: code)
    }

    /// `data.<code>.data.data` 为 `"HHMM price volume [amount]"`；昨收取 qt 字段。
    static func parseTencentMinute(_ data: Data, code: String) -> GlobalMinuteSeries {
        guard
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let root = json["data"] as? [String: Any],
            let node = root[code] as? [String: Any]
        else { return GlobalMinuteSeries(bars: [], preClose: nil) }

        let preClose: Double? = {
            if let qt = node["qt"] as? [String: Any] {
                let row = (qt[code] as? [Any]) ?? (qt.values.first as? [Any])
                if let row, row.count > 4, let pre = Double("\(row[4])"), pre > 0 { return pre }
            }
            return nil
        }()

        let dayToken: String? = {
            if let d = (node["data"] as? [String: Any])?["date"] as? String, !d.isEmpty { return d }
            return nil
        }()

        let rows = ((node["data"] as? [String: Any])?["data"] as? [String]) ?? []
        let tz = code.hasPrefix("us") ? "America/New_York"
            : (code.hasPrefix("hk") ? "Asia/Hong_Kong" : "Asia/Shanghai")
        let bars: [GlobalIndexBar] = rows.compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count >= 2,
                  let price = Double(parts[1]), price > 0,
                  let date = minuteDate(day: dayToken, hm: String(parts[0]), timeZone: tz)
            else { return nil }
            let vol = parts.count >= 3 ? Double(parts[2]) : nil
            let amt = parts.count >= 4 ? Double(parts[3]) : nil
            return GlobalIndexBar(
                date: date, open: price, high: price, low: price, close: price,
                volume: vol, turnover: amt
            )
        }
        return GlobalMinuteSeries(bars: bars, preClose: preClose)
    }

    private static func minuteDate(day: String?, hm: String, timeZone: String) -> Date? {
        guard hm.count >= 3, let minutes = Int(hm) else { return nil }
        let h = minutes / 100
        let m = minutes % 100
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZone) ?? .current
        let base: Date
        if let day, day.count == 8 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = cal.timeZone
            f.dateFormat = "yyyyMMdd"
            guard let d = f.date(from: day) else { return nil }
            base = d
        } else {
            base = Date()
        }
        var c = cal.dateComponents([.year, .month, .day], from: base)
        c.hour = h
        c.minute = m
        c.second = 0
        return cal.date(from: c)
    }

    // MARK: - K 线

    /// 最近 `count` 根 K 线，按日期升序。
    public func klineHistory(for index: GlobalIndex, period: KLinePeriod, count: Int = 800) async -> [GlobalIndexBar] {
        switch index.history {
        case .tencent(let code):
            let url = "https://ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(code),\(period.rawValue),,,\(count),qfq"
            guard let data = await fetchData(url, referer: "https://gu.qq.com/") else { return [] }
            return Array(Self.parseTencentKLine(data, code: code, period: period).suffix(count))
        case .sina(let symbol):
            guard period == .day else {
                // 外盘周/月：先拉日线再聚合。
                let daily = await klineHistory(for: index, period: .day, count: max(count * 6, 800))
                return Array(Self.aggregate(daily, period: period).suffix(count))
            }
            let url = "https://gi.finance.sina.com.cn/hq/daily?symbol=\(symbol)&num=\(count)"
            guard let data = await fetchData(url, referer: "https://finance.sina.com.cn/") else { return [] }
            return Array(Self.parseSinaDaily(data).suffix(count))
        case nil:
            return []
        }
    }

    /// 兼容旧调用。
    public func dailyHistory(for index: GlobalIndex, count: Int = 800) async -> [GlobalIndexBar] {
        await klineHistory(for: index, period: .day, count: count)
    }

    private func fetchData(_ urlString: String, referer: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        return try? await session.data(for: request).0
    }

    /// `data.<code>.day|week|month`：`[日期, 开, 收, 高, 低, 量]`
    static func parseTencentKLine(_ data: Data, code: String, period: KLinePeriod) -> [GlobalIndexBar] {
        guard
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let root = json["data"] as? [String: Any],
            let node = root[code] as? [String: Any]
        else { return [] }
        let keys: [String]
        switch period {
        case .day: keys = ["qfqday", "day"]
        case .week: keys = ["qfqweek", "week"]
        case .month: keys = ["qfqmonth", "month"]
        }
        var rows: [[Any]] = []
        for key in keys {
            if let arr = node[key] as? [[Any]] { rows = arr; break }
        }
        return rows.compactMap { row in
            guard row.count >= 5,
                  let date = dayDate("\(row[0])"),
                  let o = Double("\(row[1])"), let c = Double("\(row[2])"),
                  let h = Double("\(row[3])"), let l = Double("\(row[4])"),
                  c > 0
            else { return nil }
            let vol = row.count > 5 ? Double("\(row[5])") : nil
            return GlobalIndexBar(date: date, open: o, high: h, low: l, close: c, volume: vol)
        }
    }

    static func parseTencentDaily(_ data: Data, code: String) -> [GlobalIndexBar] {
        parseTencentKLine(data, code: code, period: .day)
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
            return GlobalIndexBar(date: date, open: o, high: h, low: l, close: c, volume: num("v"))
        }
    }

    /// 由日线聚合成周线 / 月线（外盘新浪源用）。
    static func aggregate(_ daily: [GlobalIndexBar], period: KLinePeriod) -> [GlobalIndexBar] {
        guard period != .day, !daily.isEmpty else { return daily }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var groups: [(Date, [GlobalIndexBar])] = []
        for bar in daily {
            let key: Date
            switch period {
            case .week:
                let week = cal.dateInterval(of: .weekOfYear, for: bar.date)?.start ?? bar.date
                key = week
            case .month:
                let comps = cal.dateComponents([.year, .month], from: bar.date)
                key = cal.date(from: comps) ?? bar.date
            case .day:
                key = bar.date
            }
            if let last = groups.last, last.0 == key {
                groups[groups.count - 1].1.append(bar)
            } else {
                groups.append((key, [bar]))
            }
        }
        return groups.compactMap { _, bars in
            guard let first = bars.first, let last = bars.last else { return nil }
            return GlobalIndexBar(
                date: last.date,
                open: first.open,
                high: bars.map(\.high).max() ?? last.high,
                low: bars.map(\.low).min() ?? last.low,
                close: last.close,
                volume: bars.compactMap(\.volume).reduce(0, +),
                turnover: bars.compactMap(\.turnover).reduce(0, +)
            )
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
