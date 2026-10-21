import Foundation

/// 腾讯行情客户端（免密钥公开接口）：
/// - 快照 + 买卖五档：qt.gtimg.cn（GBK 文本，批量 ≤50 代码/请求）
/// - K线（日/周/1分/5分）与分时：ifzq.gtimg.cn（UTF-8 JSON）
public struct TencentMarketClient: Sendable {

    public enum Period: String, Sendable {
        case day, week, min1 = "m1", min5 = "m5"
    }

    public struct Snapshot: Sendable {
        public let quote: Quote
        public let book: OrderBook
    }

    public struct KLineFetch: Sendable {
        public let bars: [KLine]
        public let preClose: Decimal?
    }

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            "Referer": "https://gu.qq.com/",
        ]
        session = URLSession(configuration: config)
    }

    public static func code(for symbol: Symbol) -> String {
        switch symbol.exchange {
        case .sse: return "sh" + symbol.code
        case .szse: return "sz" + symbol.code
        case .bse: return "bj" + symbol.code
        }
    }

    // MARK: - 快照（含五档）

    public func snapshots(for symbols: [Symbol]) async throws -> [Snapshot] {
        guard !symbols.isEmpty else { return [] }
        let codes = symbols.map(Self.code).joined(separator: ",")
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(codes)") else { return [] }
        let (data, _) = try await session.data(from: url)
        guard let text = GB18030.decode(data) else {
            throw ServiceError.backend("行情文本解码失败")
        }
        return Self.parseSnapshots(text, symbols: symbols)
    }

    static func parseSnapshots(_ text: String, symbols: [Symbol]) -> [Snapshot] {
        let byCode = Dictionary(uniqueKeysWithValues: symbols.map { (code(for: $0), $0) })
        var out: [Snapshot] = []
        for rawLine in text.split(whereSeparator: { $0 == ";" || $0 == "\n" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("v_"), let eq = line.firstIndex(of: "=") else { continue }
            let codeName = String(line[line.index(line.startIndex, offsetBy: 2)..<eq])
            guard let symbol = byCode[codeName] else { continue }
            var body = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("\"") { body.removeFirst() }
            if body.hasSuffix("\"") { body.removeLast() }
            let f = body.components(separatedBy: "~")
            guard f.count > 48 else { continue }

            func dec(_ i: Int) -> Decimal { Decimal(string: f[i].isEmpty ? "0" : f[i]) ?? 0 }
            func lots(_ i: Int) -> Int { Int(((Double(f[i]) ?? 0)).rounded()) * 100 }

            let last = dec(3)
            guard last > 0 else { continue } // 停牌/无效快照

            let preClose = dec(4)
            let upper = dec(47) > 0 ? dec(47) : preClose * (1 + symbol.limitRate)
            let lower = dec(48) > 0 ? dec(48) : preClose * (1 - symbol.limitRate)

            var bids: [OrderBook.Level] = []
            var asks: [OrderBook.Level] = []
            for i in 0..<5 {
                let bp = dec(9 + i * 2)
                let bv = lots(10 + i * 2)
                if bp > 0 { bids.append(.init(price: bp, volume: bv)) }
                let ap = dec(19 + i * 2)
                let av = lots(20 + i * 2)
                if ap > 0 { asks.append(.init(price: ap, volume: av)) }
            }

            let timestamp = Self.parseTimestamp(f[30]) ?? Date()
            let quote = Quote(
                symbol: symbol.fullCode,
                lastPrice: last,
                open: dec(5),
                high: dec(33),
                low: dec(34),
                preClose: preClose,
                bidPrice1: bids.first?.price ?? last,
                askPrice1: asks.first?.price ?? last,
                bidVolume1: bids.first?.volume ?? 0,
                askVolume1: asks.first?.volume ?? 0,
                volume: Int64(lots(6)),
                turnover: dec(37) * 10_000, // 接口为万元
                upperLimit: upper,
                lowerLimit: lower,
                timestamp: timestamp
            )
            let book = OrderBook(symbol: symbol.fullCode, asks: asks, bids: bids, timestamp: timestamp)
            out.append(Snapshot(quote: quote, book: book))
        }
        return out
    }

    static func parseTimestamp(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyyMMddHHmmss"
        return f.date(from: s)
    }

    // MARK: - K 线

    public func klines(for symbol: Symbol, period: Period, count: Int) async throws -> KLineFetch {
        let code = Self.code(for: symbol)
        let url: URL?
        switch period {
        case .day, .week:
            url = URL(string: "https://ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(code),\(period.rawValue),,,\(count),qfq")
        case .min1, .min5:
            url = URL(string: "https://ifzq.gtimg.cn/appstock/app/kline/mkline?param=\(code),\(period.rawValue),,\(count)")
        }
        guard let url else { return KLineFetch(bars: [], preClose: nil) }
        let (data, _) = try await session.data(from: url)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard
            let root = json?["data"] as? [String: Any],
            let node = root[code] as? [String: Any]
        else {
            return KLineFetch(bars: [], preClose: nil)
        }

        let prec: Decimal? = {
            if let s = node["prec"] as? String { return Decimal(string: s) }
            if let d = node["prec"] as? Double { return Decimal(d) }
            return nil
        }()

        let keyCandidates: [String]
        switch period {
        case .day: keyCandidates = ["qfqday", "day"]
        case .week: keyCandidates = ["qfqweek", "week"]
        case .min1: keyCandidates = ["m1"]
        case .min5: keyCandidates = ["m5"]
        }
        var rows: [[Any]] = []
        for key in keyCandidates {
            if let arr = node[key] as? [[Any]] {
                rows = arr
                break
            }
        }

        let isMinute = period == .min1 || period == .min5
        var bars: [KLine] = []
        bars.reserveCapacity(rows.count)
        for row in rows {
            guard row.count >= 6 else { continue }
            let dateStr = "\(row[0])"
            guard let ts = isMinute ? Self.parseMinuteDate(dateStr) : Self.parseDayDate(dateStr) else { continue }
            guard
                let open = Double("\(row[1])"), let close = Double("\(row[2])"),
                let high = Double("\(row[3])"), let low = Double("\(row[4])"),
                let volLots = Double("\(row[5])")
            else { continue }
            let shares = Int64((volLots * 100).rounded())
            let mid = (open + close) / 2
            let tick = symbol.priceTick
            bars.append(KLine(
                timestamp: ts,
                open: Decimal(open).quantized(to: tick),
                high: Decimal(high).quantized(to: tick),
                low: Decimal(low).quantized(to: tick),
                close: Decimal(close).quantized(to: tick),
                volume: shares,
                turnover: Decimal(mid * Double(shares)).quantized(to: tick)
            ))
        }
        return KLineFetch(bars: bars, preClose: prec)
    }

    static func parseDayDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    static func parseMinuteDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyyMMddHHmm"
        return f.date(from: s)
    }
}
