import Foundation

/// A股交易时段判定（Asia/Shanghai）。
/// 用于真实行情适配层决定轮询频率，以及 UI 的会话态提示。
public enum MarketSession {

    public static var shanghaiCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }

    /// 细粒度会话相位（含集合竞价 / 午休等）。
    public enum Phase: String, Sendable, Equatable {
        case weekend        // 周末
        case preOpen        // 开盘前（0:00–9:15）
        case callAuction    // 集合竞价 9:15–9:25
        case continuousAM   // 上午连续竞价 9:30–11:30
        case lunch          // 午休
        case continuousPM   // 下午连续竞价 13:00–15:00
        case afterClose     // 收盘后（当日）
        case closed         // 非交易日（节假日等，当前按工作日日历简化）

        public var label: String {
            switch self {
            case .weekend: return "周末休市"
            case .preOpen: return "开盘前"
            case .callAuction: return "集合竞价"
            case .continuousAM: return "交易中 · 上午"
            case .continuousPM: return "交易中 · 下午"
            case .lunch: return "午休"
            case .afterClose: return "已收盘"
            case .closed: return "休市"
            }
        }

        /// 是否处于需要较高行情刷新频率的时段（含集合竞价）。
        public var isActiveTrading: Bool {
            switch self {
            case .callAuction, .continuousAM, .continuousPM: return true
            default: return false
            }
        }

        /// 顶栏短标签。
        public var shortLabel: String {
            switch self {
            case .weekend: return "周末"
            case .preOpen: return "开盘前"
            case .callAuction: return "集合竞价"
            case .continuousAM, .continuousPM: return "交易中"
            case .lunch: return "午休"
            case .afterClose: return "已收盘"
            case .closed: return "休市"
            }
        }
    }

    public static func phase(at date: Date = Date()) -> Phase {
        let cal = shanghaiCalendar
        let weekday = cal.component(.weekday, from: date) // 1=周日
        guard (2...6).contains(weekday) else { return .weekend }
        let minutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        switch minutes {
        case ..<(9 * 60 + 15): return .preOpen
        case (9 * 60 + 15)..<(9 * 60 + 25): return .callAuction
        case (9 * 60 + 25)..<(9 * 60 + 30): return .callAuction // 9:25–9:30 撮合等待，仍标集合竞价
        case (9 * 60 + 30)...(11 * 60 + 30): return .continuousAM
        case (11 * 60 + 31)..<(13 * 60): return .lunch
        case (13 * 60)...(15 * 60): return .continuousPM
        default: return .afterClose
        }
    }

    /// 是否处于连续竞价时段（含集合竞价 9:15 起，收盘后 2 分钟容差）
    public static func isOpen(at date: Date = Date()) -> Bool {
        let p = phase(at: date)
        switch p {
        case .callAuction, .continuousAM, .continuousPM: return true
        case .afterClose:
            // 收盘后 2 分钟容差，兼容旧轮询逻辑
            let cal = shanghaiCalendar
            let minutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
            return minutes <= 15 * 60 + 2
        default: return false
        }
    }

    /// 最近的交易日（含当天，若为工作日）
    public static func latestTradingDay(from date: Date = Date()) -> Date {
        let cal = shanghaiCalendar
        var day = cal.startOfDay(for: date)
        while [1, 7].contains(cal.component(.weekday, from: day)) {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return day
    }
}
