import Foundation

/// 全球主要股指（只读看盘，不参与撮合）。
public struct GlobalIndex: Sendable, Identifiable, Hashable {
    public enum Region: String, Sendable, CaseIterable {
        case asia = "亚太"
        case europe = "欧洲"
        case americas = "美洲"
    }

    public enum Source: Sendable, Hashable {
        /// qt.gtimg.cn 代码，如 sh000001 / hkHSI / usDJI
        case tencent(String)
        /// hq.sinajs.cn 代码，如 znb_NKY
        case sina(String)
    }

    /// 交易时段：当地时区内、自零点起的分钟区间。
    public struct Session: Sendable, Hashable {
        public let timeZone: String
        public let ranges: [ClosedRange<Int>]
    }

    public let id: String
    public let name: String
    public let market: String
    public let region: Region
    public let source: Source
    public let session: Session

    /// 按常规时段与周一至周五判断，不含各地节假日。
    public func isTrading(at date: Date) -> Bool {
        guard let tz = TimeZone(identifier: session.timeZone) else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = c.weekday, (2...6).contains(weekday) else { return false }
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return session.ranges.contains { $0.contains(minute) }
    }
}

public extension GlobalIndex {
    private static func s(_ tz: String, _ ranges: ClosedRange<Int>...) -> Session {
        Session(timeZone: tz, ranges: ranges)
    }

    private static let cn = s("Asia/Shanghai", 570...690, 780...900)
    private static let hk = s("Asia/Hong_Kong", 570...720, 780...960)
    private static let us = s("America/New_York", 570...960)

    static let catalog: [GlobalIndex] = [
        .init(id: "sh000001", name: "上证指数", market: "上海", region: .asia, source: .tencent("sh000001"), session: cn),
        .init(id: "sz399001", name: "深证成指", market: "深圳", region: .asia, source: .tencent("sz399001"), session: cn),
        .init(id: "sz399006", name: "创业板指", market: "深圳", region: .asia, source: .tencent("sz399006"), session: cn),
        .init(id: "hkHSI", name: "恒生指数", market: "香港", region: .asia, source: .tencent("hkHSI"), session: hk),
        .init(id: "hkHSTECH", name: "恒生科技", market: "香港", region: .asia, source: .tencent("hkHSTECH"), session: hk),
        .init(id: "NKY", name: "日经225", market: "东京", region: .asia, source: .sina("znb_NKY"),
              session: s("Asia/Tokyo", 540...690, 750...930)),
        .init(id: "KOSPI", name: "韩国综合", market: "首尔", region: .asia, source: .sina("znb_KOSPI"),
              session: s("Asia/Seoul", 540...930)),
        .init(id: "TWJQ", name: "台湾加权", market: "台北", region: .asia, source: .sina("znb_TWJQ"),
              session: s("Asia/Taipei", 540...810)),
        .init(id: "FSSTI", name: "新加坡海峡", market: "新加坡", region: .asia, source: .sina("znb_FSSTI"),
              session: s("Asia/Singapore", 540...720, 780...1020)),
        .init(id: "SENSEX", name: "印度SENSEX", market: "孟买", region: .asia, source: .sina("znb_SENSEX"),
              session: s("Asia/Kolkata", 555...930)),
        .init(id: "AS51", name: "澳洲ASX200", market: "悉尼", region: .asia, source: .sina("znb_AS51"),
              session: s("Australia/Sydney", 600...960)),

        .init(id: "SX5E", name: "欧洲斯托克50", market: "欧元区", region: .europe, source: .sina("znb_SX5E"),
              session: s("Europe/Berlin", 540...1050)),
        .init(id: "DAX", name: "德国DAX", market: "法兰克福", region: .europe, source: .sina("znb_DAX"),
              session: s("Europe/Berlin", 540...1050)),
        .init(id: "UKX", name: "英国富时100", market: "伦敦", region: .europe, source: .sina("znb_UKX"),
              session: s("Europe/London", 480...990)),
        .init(id: "CAC", name: "法国CAC40", market: "巴黎", region: .europe, source: .sina("znb_CAC"),
              session: s("Europe/Paris", 540...1050)),
        .init(id: "SMI", name: "瑞士SMI", market: "苏黎世", region: .europe, source: .sina("znb_SMI"),
              session: s("Europe/Zurich", 540...1050)),

        .init(id: "usDJI", name: "道琼斯", market: "纽约", region: .americas, source: .tencent("usDJI"), session: us),
        .init(id: "usIXIC", name: "纳斯达克", market: "纽约", region: .americas, source: .tencent("usIXIC"), session: us),
        .init(id: "usINX", name: "标普500", market: "纽约", region: .americas, source: .tencent("usINX"), session: us),
        .init(id: "SPTSX", name: "加拿大TSX", market: "多伦多", region: .americas, source: .sina("znb_SPTSX"),
              session: s("America/Toronto", 570...960)),
        .init(id: "IBOV", name: "巴西IBOV", market: "圣保罗", region: .americas, source: .sina("znb_IBOV"),
              session: s("America/Sao_Paulo", 600...1020)),
    ]
}

public struct GlobalIndexQuote: Sendable, Hashable {
    public let id: String
    public let last: Double
    public let change: Double
    public let changePercent: Double
    public let high: Double?
    public let low: Double?
}
