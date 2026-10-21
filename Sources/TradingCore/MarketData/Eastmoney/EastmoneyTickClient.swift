import Foundation

/// 东方财富逐笔成交客户端（免密钥公开接口）。
/// 注意：该接口仅覆盖当前交易时段；休市日返回空列表。
public struct EastmoneyTickClient: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            "Referer": "https://quote.eastmoney.com/",
        ]
        session = URLSession(configuration: config)
    }

    static func secid(for symbol: Symbol) -> String {
        (symbol.exchange == .sse ? "1" : "0") + "." + symbol.code
    }
    /// 最近逐笔（时间顺序，旧→新）
    public func recentTicks(symbol: Symbol, limit: Int = 60) async throws -> [Tick] {
        let secid = Self.secid(for: symbol)
        guard let url = URL(string: "https://push2his.eastmoney.com/api/qt/stock/details/get?secid=\(secid)&pos=-\(limit)&fields1=f1,f2,f3,f4&fields2=f51,f52,f53,f54,f55") else {
            return []
        }
        let (data, _) = try await session.data(from: url)
        guard
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let node = json["data"] as? [String: Any],
            let details = node["details"] as? [String]
        else {
            return []
        }
        let day = MarketSession.latestTradingDay()
        var ticks: [Tick] = []
        ticks.reserveCapacity(details.count)
        for (i, row) in details.enumerated() {
            let parts = row.components(separatedBy: ",")
            guard parts.count >= 3 else { continue }
            guard let price = Decimal(string: parts[1]) else { continue }
            let lots = Int((Double(parts[2]) ?? 0).rounded())
            guard lots > 0, price > 0 else { continue }
            let direction = Self.direction(from: parts.last ?? "")
            ticks.append(Tick(
                id: UInt64(i),
                symbol: symbol.fullCode,
                price: price,
                volume: lots * 100,
                direction: direction,
                timestamp: Self.timestamp(day: day, time: parts[0]) ?? day
            ))
        }
        return ticks
    }

    static func direction(from token: String) -> TickDirection {
        switch token.trimmingCharacters(in: .whitespaces) {
        case "1", "B", "b": return .buy    // 外盘
        case "2", "S", "s": return .sell   // 内盘
        default: return .neutral
        }
    }

    static func timestamp(day: Date, time: String) -> Date? {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let s = parts.count >= 3 ? Int(parts[2]) ?? 0 : 0
        let cal = MarketSession.shanghaiCalendar
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = h
        comps.minute = m
        comps.second = s
        return cal.date(from: comps)
    }
}
