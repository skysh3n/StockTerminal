import Foundation

/// 交易所
public enum Exchange: String, Codable, Sendable, Hashable, CaseIterable {
    case sse = "SH"    // 上交所
    case szse = "SZ"   // 深交所
    case bse = "BJ"    // 北交所
}

/// K线周期
public enum TimeFrame: String, Codable, Sendable, Hashable, CaseIterable {
    case timeShare    // 分时（当日分钟序列）
    case min1
    case min5
    case day
    case week

    /// 界面显示文案
    public var label: String {
        switch self {
        case .timeShare: return "分时"
        case .min1: return "1分"
        case .min5: return "5分"
        case .day: return "日K"
        case .week: return "周K"
        }
    }

    /// 每根 bar 的秒数；分时按分钟处理
    public var seconds: TimeInterval {
        switch self {
        case .timeShare, .min1: return 60
        case .min5: return 300
        case .day: return 86400
        case .week: return 604800
        }
    }

    public var isTimeShare: Bool { self == .timeShare }

    /// 图表周期切换顺序
    public static let chartCases: [TimeFrame] = [.timeShare, .min1, .min5, .day, .week]
}

/// 买卖方向
public enum OrderSide: String, Codable, Sendable, Hashable {
    case buy, sell
    public var label: String { self == .buy ? "买入" : "卖出" }
    public var shortLabel: String { self == .buy ? "买" : "卖" }
}

/// 委托类型
public enum OrderType: String, Codable, Sendable, Hashable {
    case limit, market
    public var label: String { self == .limit ? "限价" : "市价" }
}

/// 委托状态
public enum OrderStatus: String, Codable, Sendable, Hashable {
    case pending        // 已报（挂单中）
    case partialFilled  // 部成
    case filled         // 已成
    case cancelling     // 撤单中
    case cancelled      // 已撤
    case rejected       // 废单

    public var label: String {
        switch self {
        case .pending: return "已报"
        case .partialFilled: return "部成"
        case .filled: return "已成"
        case .cancelling: return "撤单中"
        case .cancelled: return "已撤"
        case .rejected: return "废单"
        }
    }

    public var isTerminal: Bool {
        self == .filled || self == .cancelled || self == .rejected
    }

    public var isCancellable: Bool {
        self == .pending || self == .partialFilled
    }
}

/// 逐笔方向（内外盘）
public enum TickDirection: String, Codable, Sendable, Hashable {
    case buy     // 外盘（主动买）
    case sell    // 内盘（主动卖）
    case neutral // 中性

    public var label: String {
        switch self {
        case .buy: return "外盘"
        case .sell: return "内盘"
        case .neutral: return "中性"
        }
    }
}
