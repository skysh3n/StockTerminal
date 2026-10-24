import Foundation

/// 价格预警方向（绝对价用涨破/跌破；涨跌幅类复用文案）。
public enum PriceAlertDirection: String, Codable, Sendable, Hashable {
    case above
    case below

    public var label: String {
        switch self {
        case .above: return "涨破"
        case .below: return "跌破"
        }
    }
}

/// 预警类型：绝对价 或 当日涨跌幅条件。
public enum PriceAlertKind: String, Codable, Sendable, Hashable {
    case absolutePrice
    case dayChangeUp      // 当日涨幅 ≥ threshold%
    case dayChangeDown    // 当日跌幅 ≤ -threshold%（threshold 为正数）

    public var label: String {
        switch self {
        case .absolutePrice: return "价格"
        case .dayChangeUp: return "涨幅≥"
        case .dayChangeDown: return "跌幅≤"
        }
    }
}

/// 本地价格/条件预警规则（不依赖券商）。
public struct PriceAlert: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var symbol: String
    public var name: String
    public var kind: PriceAlertKind
    public var direction: PriceAlertDirection
    public var threshold: Decimal
    public var enabled: Bool
    public var triggeredAt: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        kind: PriceAlertKind = .absolutePrice,
        direction: PriceAlertDirection,
        threshold: Decimal,
        enabled: Bool = true,
        triggeredAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.kind = kind
        self.direction = direction
        self.threshold = threshold
        self.enabled = enabled
        self.triggeredAt = triggeredAt
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(PriceAlertKind.self, forKey: .kind) ?? .absolutePrice
        direction = try c.decode(PriceAlertDirection.self, forKey: .direction)
        threshold = try c.decode(Decimal.self, forKey: .threshold)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        triggeredAt = try c.decodeIfPresent(Date.self, forKey: .triggeredAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

/// 公告列表条目（只读，外链打开正文）。
public struct StockNotice: Sendable, Hashable, Identifiable {
    public var id: String { artCode.isEmpty ? "\(symbol)-\(title)-\(noticeDate)" : artCode }
    public let artCode: String
    public let symbol: String
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
