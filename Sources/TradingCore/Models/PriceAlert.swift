import Foundation

/// 价格预警方向。
public enum PriceAlertDirection: String, Codable, Sendable, Hashable {
    case above   // 涨破
    case below   // 跌破

    public var label: String {
        switch self {
        case .above: return "涨破"
        case .below: return "跌破"
        }
    }
}

/// 本地价格预警规则（不依赖券商）。
public struct PriceAlert: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var symbol: String        // fullCode
    public var name: String
    public var direction: PriceAlertDirection
    public var threshold: Decimal
    public var enabled: Bool
    public var triggeredAt: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        direction: PriceAlertDirection,
        threshold: Decimal,
        enabled: Bool = true,
        triggeredAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.direction = direction
        self.threshold = threshold
        self.enabled = enabled
        self.triggeredAt = triggeredAt
        self.createdAt = createdAt
    }
}

/// 公告列表条目（只读，外链打开正文）。
public struct StockNotice: Sendable, Hashable, Identifiable {
    public var id: String { artCode.isEmpty ? "\(symbol)-\(title)-\(noticeDate)" : artCode }
    public let artCode: String
    public let symbol: String        // 6 位代码
    public let title: String
    public let noticeDate: String
    public let url: URL?

    public init(artCode: String, symbol: String, title: String, noticeDate: String, url: URL?) {
        self.artCode = artCode
        self.symbol = symbol
        self.title = title
        self.noticeDate = noticeDate
        self.url = url
    }
}
