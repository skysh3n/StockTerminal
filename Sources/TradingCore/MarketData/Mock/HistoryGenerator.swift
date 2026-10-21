import Foundation

/// 某标的的全套历史数据（各周期一致收敛于同一个「当前价」）。
public struct SymbolHistory: Sendable {
    public var preClose: Decimal        // 昨收
    public var openToday: Decimal       // 今开
    public var lastPrice: Decimal       // 当前价（= 形成中分钟 bar 的开盘）
    public var upperLimit: Decimal
    public var lowerLimit: Decimal
    public var elapsedMinutes: Int      // 今日已完成分钟数

    public var day: [KLine]             // 日K，截止昨日
    public var week: [KLine]            // 周K，不含本周
    public var weekSeed: KLine?         // 本周（周一..昨日）部分 bar
    public var daySeed: KLine           // 今日形成中的日K bar
    public var timeShare: [KLine]       // 今日已完成分钟 bar（分时 = 1分共用）
    public var minuteSeed: KLine        // 形成中的分钟 bar
    public var min5: [KLine]            // 过去日细分 + 今日已完成 5分
    public var min5Seed: KLine          // 形成中的 5分 bar
}

/// 带种子的历史 K 线生成器：长期趋势(fBm) + 波动率聚集 + bar 内多步游走 + 量价相关，
/// 生成结果自洽（high ≥ max(o,c)、low ≤ min(o,c)）且视觉逼真。
public enum HistoryGenerator {

    public static func build(symbol: Symbol, seed: UInt64, basePrice: Decimal, now: Date = Date()) -> SymbolHistory {
        var rng = SplitMix64(seed: seed)
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // 周一为一周起始
        let tick = symbol.priceTick
        let today0 = cal.startOfDay(for: now)
        let lastTradingDay = previousTradingDay(before: today0, cal: cal)

        // 1) 日K：380 根，截止最近交易日（= 昨日）
        var days: [Date] = []
        var d = lastTradingDay
        while days.count < 380 {
            days.append(d)
            d = previousTradingDay(before: d, cal: cal)
        }
        days.reverse()

        let daily = walkBars(
            rng: &rng, start: basePrice.doubleValue, timestamps: days,
            baseVol: 0.016, subSteps: 8, tick: tick
        ) { i, absRet, r in
            // 日成交量：量价相关 + 慢变活跃度
            let activity = 1 + 0.6 * sin(Double(i) / 23 + r.unitDouble() * 0.3)
            let lots = Double(30_000) * activity * (1 + absRet * 25) * r.range(0.6, 1.5)
            return Int64(lots * 100)
        }

        let preClose = daily.last?.close ?? basePrice
        let limitRate = symbol.limitRate
        let upperLimit = (preClose * (1 + limitRate)).quantized(to: tick)
        let lowerLimit = (preClose * (1 - limitRate)).quantized(to: tick)

        // 2) 周K：按周分组；本周（含昨日之前的部分）单独作为 weekSeed
        let thisMonday = cal.dateInterval(of: .weekOfYear, for: today0)?.start ?? today0
        var weekGroups: [Date: [KLine]] = [:]
        var weekOrder: [Date] = []
        for bar in daily {
            let ws = cal.dateInterval(of: .weekOfYear, for: bar.timestamp)?.start ?? bar.timestamp
            if weekGroups[ws] == nil { weekOrder.append(ws) }
            weekGroups[ws, default: []].append(bar)
        }
        var weekly: [KLine] = []
        var weekSeed: KLine?
        for ws in weekOrder {
            guard let group = weekGroups[ws], let merged = mergeBars(group, at: ws) else { continue }
            if ws == thisMonday { weekSeed = merged } else { weekly.append(merged) }
        }

        // 3) 今日分钟路径：openGap → 逐分钟游走
        let elapsed = decideElapsed(now: now, cal: cal, seed: seed)
        let gap = rng.gaussian() * 0.004
        var openToday = (preClose * Decimal(1 + gap)).quantized(to: tick)
        openToday = min(max(openToday, lowerLimit), upperLimit)

        let anchor = openToday.doubleValue
        var mPrice = anchor
        var mRegime = 0.0012
        var minuteBars: [KLine] = []
        minuteBars.reserveCapacity(elapsed)
        for i in 0..<elapsed {
            mRegime += (0.0012 - mRegime) * 0.05 + rng.gaussian() * 0.0002
            mRegime = min(max(mRegime, 0.0004), 0.004)
            let open = mPrice
            var hi = open, lo = open, cur = open
            for _ in 0..<4 {
                // 轻微均值回归防止漂出涨跌停
                let revert = (anchor - cur) / max(anchor, 1e-9) * 0.02
                let r = revert + mRegime * rng.gaussian() / 2
                cur *= (1 + r)
                hi = max(hi, cur)
                lo = min(lo, cur)
            }
            cur = clampPrice(cur, lower: lowerLimit, upper: upperLimit)
            hi = clampPrice(hi, lower: lowerLimit, upper: upperLimit)
            lo = clampPrice(lo, lower: lowerLimit, upper: upperLimit)
            // U 型日内成交量（开盘/尾盘活跃）
            let shape = 0.55 + 1.7 * exp(-Double(i) / 28) + 1.3 * exp(-Double(elapsed - 1 - i) / 28)
            let vol = Int64(Double(260) * shape * rng.range(0.5, 1.6)) * 100
            let oD = Decimal(open).quantized(to: tick)
            let cD = Decimal(cur).quantized(to: tick)
            let hD = max(Decimal(hi).quantized(to: tick), oD, cD)
            let lD = min(Decimal(lo).quantized(to: tick), oD, cD)
            let mid = (hD + lD) / 2
            minuteBars.append(KLine(
                timestamp: sessionTime(minuteIndex: i, day: today0, cal: cal),
                open: oD, high: hD, low: lD, close: cD,
                volume: vol, turnover: mid * Decimal(vol)
            ))
            mPrice = cur
        }

        let lastPrice = minuteBars.last?.close ?? openToday

        // 4) 今日形成中的日K bar
        let daySeed: KLine = {
            var high = openToday, low = openToday
            var vol: Int64 = 0
            var turnover = Decimal.zero
            for b in minuteBars {
                high = max(high, b.high)
                low = min(low, b.low)
                vol += b.volume
                turnover += b.turnover
            }
            return KLine(timestamp: today0, open: openToday, high: max(high, lastPrice),
                         low: min(low, lastPrice), close: lastPrice, volume: vol, turnover: turnover)
        }()

        // 5) 形成中的分钟 bar
        let minuteSeed = KLine(
            timestamp: sessionTime(minuteIndex: min(elapsed, 239), day: today0, cal: cal),
            open: lastPrice, high: lastPrice, low: lastPrice, close: lastPrice,
            volume: 0, turnover: 0
        )

        // 6) 5分K：过去 12 个交易日细分 + 今日已完成 5分组
        var min5: [KLine] = []
        let subdivCount = min(12, daily.count)
        for dayBar in daily.suffix(subdivCount) {
            min5.append(contentsOf: subdivideTo5Min(dayBar, rng: &rng, cal: cal))
        }
        let fullGroups = elapsed / 5
        for g in 0..<fullGroups {
            let chunk = Array(minuteBars[(g * 5)..<min(g * 5 + 5, minuteBars.count)])
            if let m = mergeBars(chunk, at: chunk.first?.timestamp ?? today0) { min5.append(m) }
        }
        // 形成中的 5分 bar：聚合当前未完成分组内的分钟
        let partial = Array(minuteBars[(fullGroups * 5)..<minuteBars.count])
        let min5Seed: KLine = {
            let groupIdx = elapsed / 5
            let ts = sessionTime(minuteIndex: min(groupIdx * 5, 239), day: today0, cal: cal)
            if partial.isEmpty {
                return KLine(timestamp: ts, open: lastPrice, high: lastPrice, low: lastPrice, close: lastPrice, volume: 0, turnover: 0)
            }
            var m = mergeBars(partial, at: ts)!
            m.close = lastPrice
            m.high = max(m.high, lastPrice)
            m.low = min(m.low, lastPrice)
            return m
        }()

        return SymbolHistory(
            preClose: preClose, openToday: openToday, lastPrice: lastPrice,
            upperLimit: upperLimit, lowerLimit: lowerLimit, elapsedMinutes: elapsed,
            day: daily, week: weekly, weekSeed: weekSeed, daySeed: daySeed,
            timeShare: minuteBars, minuteSeed: minuteSeed, min5: min5, min5Seed: min5Seed
        )
    }

    // MARK: - 合并 / 工具

    /// 将多根 bar 合并为一根（timestamp 指定）
    public static func mergeBars(_ bars: [KLine], at timestamp: Date) -> KLine? {
        guard let first = bars.first else { return nil }
        var high = first.high, low = first.low, close = first.close
        var vol = first.volume, turnover = first.turnover
        for b in bars.dropFirst() {
            high = max(high, b.high)
            low = min(low, b.low)
            close = b.close
            vol += b.volume
            turnover += b.turnover
        }
        return KLine(timestamp: timestamp, open: first.open, high: high, low: low, close: close, volume: vol, turnover: turnover)
    }

    /// 本周一 00:00
    public static func startOfWeek(_ date: Date, cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }()) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// A股交易时段：分钟序号 [0,240) → 当日时间（9:30-11:30, 13:00-15:00）
    public static func sessionTime(minuteIndex: Int, day: Date, cal: Calendar = Calendar(identifier: .gregorian)) -> Date {
        let idx = max(0, min(minuteIndex, 239))
        let offset: TimeInterval = idx < 120
            ? TimeInterval(9 * 3600 + 30 * 60 + idx * 60)
            : TimeInterval(13 * 3600 + (idx - 120) * 60)
        return day.addingTimeInterval(offset)
    }

    /// 判定「当前时刻」对应今日已完成分钟数：盘中用真实时间，其余时段模拟一个盘中时点
    static func decideElapsed(now: Date, cal: Calendar, seed: UInt64) -> Int {
        let weekday = cal.component(.weekday, from: now)
        let t = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        if (2...6).contains(weekday) {
            if t >= 570 && t < 690 { return max(10, t - 570) }          // 9:30-11:30
            if t >= 690 && t < 780 { return 120 }                        // 午休
            if t >= 780 && t < 870 { return 120 + (t - 780) }            // 13:00-15:00
            if t >= 870 { return 238 }                                   // 收盘后
        }
        return 95 + Int(seed % 80)                                       // 盘前/周末：模拟盘中
    }

    static func previousTradingDay(before date: Date, cal: Calendar) -> Date {
        var d = cal.date(byAdding: .day, value: -1, to: date) ?? date
        while [1, 7].contains(cal.component(.weekday, from: d)) {
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return cal.startOfDay(for: d)
    }

    private static func clampPrice(_ p: Double, lower: Decimal, upper: Decimal) -> Double {
        min(max(p, lower.doubleValue), upper.doubleValue)
    }

    /// 通用 bar 序列生成：波动率聚集 + 双正弦慢趋势(fBm感) + bar 内多步游走
    private static func walkBars(
        rng: inout SplitMix64,
        start: Double,
        timestamps: [Date],
        baseVol: Double,
        subSteps: Int,
        tick: Decimal,
        volume: (Int, Double, inout SplitMix64) -> Int64
    ) -> [KLine] {
        var regime = baseVol
        var price = start
        var trendPhase = rng.unitDouble() * .pi * 2
        var bars: [KLine] = []
        bars.reserveCapacity(timestamps.count)

        for (i, ts) in timestamps.enumerated() {
            regime += (baseVol - regime) * 0.06 + rng.gaussian() * baseVol * 0.10
            regime = min(max(regime, baseVol * 0.35), baseVol * 3)
            trendPhase += 0.05 + rng.unitDouble() * 0.02
            let trend = (sin(trendPhase) * 0.6 + sin(trendPhase * 2.7 + 1.3) * 0.3) * baseVol * 0.55
                + rng.gaussian() * baseVol * 0.15

            let open = price
            var hi = open, lo = open, cur = open
            for _ in 0..<subSteps {
                let r = trend / Double(subSteps) + regime * rng.gaussian() / sqrt(Double(subSteps))
                cur *= (1 + r)
                hi = max(hi, cur)
                lo = min(lo, cur)
            }
            cur = max(cur, 0.5)
            hi = max(hi, cur)
            lo = max(min(lo, cur), 0.1)

            let oD = Decimal(open).quantized(to: tick)
            let cD = Decimal(cur).quantized(to: tick)
            let hD = max(Decimal(hi).quantized(to: tick), oD, cD)
            let lD = min(Decimal(lo).quantized(to: tick), oD, cD)
            let vol = volume(i, abs(cur / max(open, 1e-9) - 1), &rng)
            let mid = (hD + lD) / 2
            bars.append(KLine(timestamp: ts, open: oD, high: hD, low: lD, close: cD,
                              volume: vol, turnover: mid * Decimal(vol)))
            price = cur
        }
        return bars
    }

    /// 将一根日K细分为 48 根 5分K（布朗桥路径保证首尾衔接开收盘）
    private static func subdivideTo5Min(_ day: KLine, rng: inout SplitMix64, cal: Calendar) -> [KLine] {
        let n = 48
        let o = max(day.open.doubleValue, 0.5)
        let c = max(day.close.doubleValue, 0.5)
        let total = log(c / o)
        let dayRange = (day.high - day.low).doubleValue / o
        let sigma = max(dayRange / 3.2, 0.0008) / sqrt(Double(n))

        // 布朗桥：B_k = sigma*(W_k - (k/n)*W_n)
        var w: [Double] = [0]
        for _ in 1...n { w.append(w.last! + rng.gaussian()) }
        let wn = w[n]
        var points: [Double] = []
        for k in 0...n {
            let bridge = sigma * (w[k] - Double(k) / Double(n) * wn)
            points.append(o * exp(total * Double(k) / Double(n) + bridge))
        }

        // 成交量按随机权重拆分
        var weights: [Double] = (0..<n).map { _ in rng.range(0.4, 1.8) }
        let wSum = weights.reduce(0, +)
        for k in 0..<n { weights[k] /= wSum }

        let dayStart = cal.startOfDay(for: day.timestamp)
        var out: [KLine] = []
        out.reserveCapacity(n)
        let tick = Decimal(string: "0.01")!
        for k in 0..<n {
            let p0 = points[k], p1 = points[k + 1]
            let jitter = sigma * 0.6
            let hi = max(p0, p1) * (1 + abs(rng.gaussian()) * jitter)
            let lo = min(p0, p1) * (1 - abs(rng.gaussian()) * jitter)
            let oD = Decimal(p0).quantized(to: tick)
            let cD = Decimal(p1).quantized(to: tick)
            let hD = max(Decimal(hi).quantized(to: tick), oD, cD)
            let lD = min(Decimal(lo).quantized(to: tick), oD, cD)
            let vol = Int64(Double(day.volume) * weights[k])
            let ts = dayStart.addingTimeInterval(k < 24
                ? TimeInterval(9 * 3600 + 30 * 60 + k * 300)
                : TimeInterval(13 * 3600 + (k - 24) * 300))
            let mid = (hD + lD) / 2
            out.append(KLine(timestamp: ts, open: oD, high: hD, low: lD, close: cD,
                             volume: vol, turnover: mid * Decimal(vol)))
        }
        return out
    }
}
