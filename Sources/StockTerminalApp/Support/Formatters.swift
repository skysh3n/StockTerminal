import Foundation
import TradingCore

/// 数字/时间格式化工具（主线程专用；formatter 全部缓存复用）。
/// 大数缩写按 A 股习惯：万手 / 亿；金额：万 / 亿。
@MainActor
enum Fmt {
    // MARK: 缓存 formatter

    private static let hhmmss: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let mmdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()

    private static let yymmdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yy/MM/dd"
        return f
    }()

    // MARK: 价格 / 涨跌

    static func price(_ d: Decimal?) -> String {
        guard let d else { return "--" }
        return String(format: "%.2f", d.doubleValue)
    }

    /// 带符号涨跌额：+12.34 / -5.67
    static func signed(_ d: Decimal?) -> String {
        guard let d else { return "--" }
        return String(format: "%+.2f", d.doubleValue)
    }

    /// 带符号百分比：+3.21%
    static func pct(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%+.2f%%", v)
    }

    // MARK: 量额

    /// 成交量：股 → 手，大数缩写（1.2万 / 3.4亿）
    static func volume(shares: Int64) -> String {
        let lots = Double(shares) / 100
        if lots >= 1e8 { return String(format: "%.2f亿", lots / 1e8) }
        if lots >= 1e4 { return String(format: "%.2f万", lots / 1e4) }
        return String(format: "%.0f", lots)
    }

    /// 成交额：元 → 万/亿
    static func amount(_ d: Decimal?) -> String {
        guard let d else { return "--" }
        let v = d.doubleValue
        if v >= 1e8 { return String(format: "%.2f亿", v / 1e8) }
        if v >= 1e4 { return String(format: "%.2f万", v / 1e4) }
        return String(format: "%.0f", v)
    }

    /// 金额（两位小数，千分位由 NumberFormatter 处理——printf 的 %, 在 Swift 里无效）
    static func money(_ d: Decimal?) -> String {
        guard let d else { return "--" }
        let v = d.doubleValue
        if abs(v) >= 1e8 { return String(format: "%.3f亿", v / 1e8) }
        if abs(v) >= 1e4 { return String(format: "%.2f万", v / 1e4) }
        return grouped.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// 整手数量文案
    static func lotsText(shares: Int) -> String {
        shares >= 100 && shares % 100 == 0 ? "\(shares / 100)手" : "\(shares)股"
    }

    // MARK: 时间

    static func clock(_ d: Date) -> String { hhmmss.string(from: d) }
    static func minute(_ d: Date) -> String { hhmm.string(from: d) }
    static func day(_ d: Date) -> String { mmdd.string(from: d) }
    static func fullDay(_ d: Date) -> String { yymmdd.string(from: d) }

    /// 图表时间轴标签：日/周K 显示日期，分钟级显示 HH:mm
    static func chartTime(_ d: Date, tf: TimeFrame) -> String {
        switch tf {
        case .day, .week: return day(d)
        case .timeShare, .min1, .min5: return minute(d)
        }
    }

    /// 委托时间：今天显示 HH:mm:ss，否则显示日期
    static func orderTime(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? clock(d) : fullDay(d)
    }
}
