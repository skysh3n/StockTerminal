import Foundation

/// A股交易时段判定（Asia/Shanghai）。
/// 用于真实行情适配层决定轮询频率（盘中 3s / 休市 30s），以及 UI 的休市提示。
public enum MarketSession {

    public static var shanghaiCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }

    /// 是否处于连续竞价时段（含集合竞价 9:15 起，收盘后 2 分钟容差）
    public static func isOpen(at date: Date = Date()) -> Bool {
        let cal = shanghaiCalendar
        let weekday = cal.component(.weekday, from: date) // 1=周日
        guard (2...6).contains(weekday) else { return false }
        let minutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let morning = minutes >= 9 * 60 + 15 && minutes <= 11 * 60 + 32
        let afternoon = minutes >= 13 * 60 && minutes <= 15 * 60 + 2
        return morning || afternoon
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
