import Foundation

/// 用实时快照合成「形成中」的日/周 K，供盘中刷新尾部蜡烛。
/// 腾讯日 K 接口（fqkline）盘中常滞后或被拦截，仅靠轮询日 K 会导致今日柱不刷新。
public enum FormingKLine {

    /// 由快照生成当前交易日（或该快照所属日）的日 K。
    public static func dayBar(from quote: Quote, priceTick: Decimal = Decimal(string: "0.01")!) -> KLine? {
        guard quote.lastPrice > 0 else { return nil }
        let cal = MarketSession.shanghaiCalendar
        let day = cal.startOfDay(for: quote.timestamp)
        let open = quote.open > 0 ? quote.open : quote.lastPrice
        let high = max(quote.high, open, quote.lastPrice)
        let lowBase = quote.low > 0 ? quote.low : min(open, quote.lastPrice)
        let low = min(lowBase, open, quote.lastPrice)
        return KLine(
            timestamp: day,
            open: open.quantized(to: priceTick),
            high: high.quantized(to: priceTick),
            low: low.quantized(to: priceTick),
            close: quote.lastPrice.quantized(to: priceTick),
            volume: quote.volume,
            turnover: quote.turnover.quantized(to: priceTick)
        )
    }

    /// 把形成中的 bar 叠到历史序列尾部：同日/同周则替换，更新的周期则追加。
    public static func overlay(_ bars: [KLine], with forming: KLine, timeFrame: TimeFrame) -> [KLine] {
        guard !bars.isEmpty else { return [forming] }
        var out = bars
        let last = out[out.count - 1]
        if sameBucket(last.timestamp, forming.timestamp, timeFrame: timeFrame) {
            out[out.count - 1] = forming
        } else if forming.timestamp > last.timestamp {
            out.append(forming)
        }
        return out
    }

    public static func sameBucket(_ a: Date, _ b: Date, timeFrame: TimeFrame) -> Bool {
        let cal = MarketSession.shanghaiCalendar
        switch timeFrame {
        case .day:
            return cal.isDate(a, inSameDayAs: b)
        case .week:
            return weekStart(a) == weekStart(b)
        default:
            return a == b
        }
    }

    /// 上海时区、周一为一周起始
    public static func weekStart(_ date: Date) -> Date {
        var cal = MarketSession.shanghaiCalendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }
}
