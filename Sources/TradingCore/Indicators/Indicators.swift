import Foundation

/// 技术指标库（纯函数，零依赖，可跨平台移植）。
/// 所有输出与输入 bar 序列按下标对齐，前置不足周期的位置为 nil。
public enum Indicators {

    // MARK: - SMA / EMA

    public static func sma(_ values: [Double], period: Int) -> [Double?] {
        let n = values.count
        guard period > 0, n > 0 else { return [Double?](repeating: nil, count: n) }
        var out = [Double?](repeating: nil, count: n)
        var sum = 0.0
        for i in 0..<n {
            sum += values[i]
            if i >= period { sum -= values[i - period] }
            if i >= period - 1 { out[i] = sum / Double(period) }
        }
        return out
    }

    public static func ema(_ values: [Double], period: Int) -> [Double?] {
        let n = values.count
        guard period > 0, n >= period else { return [Double?](repeating: nil, count: n) }
        var out = [Double?](repeating: nil, count: n)
        var seed = 0.0
        for i in 0..<period { seed += values[i] }
        var prev = seed / Double(period)
        out[period - 1] = prev
        let k = 2.0 / Double(period + 1)
        for i in period..<n {
            prev = values[i] * k + prev * (1 - k)
            out[i] = prev
        }
        return out
    }

    // MARK: - MACD（12, 26, 9）

    public static func macd(
        _ closes: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9
    ) -> (dif: [Double?], dea: [Double?], hist: [Double?]) {
        let n = closes.count
        let eFast = ema(closes, period: fast)
        let eSlow = ema(closes, period: slow)

        var dif = [Double?](repeating: nil, count: n)
        for i in 0..<n {
            if let a = eFast[i], let b = eSlow[i] { dif[i] = a - b }
        }
        // DEA = DIF 的 EMA(signal)：压缩非 nil 段计算后映射回原下标
        var dea = [Double?](repeating: nil, count: n)
        let validIdx = (0..<n).filter { dif[$0] != nil }
        if validIdx.count >= signal {
            let compact = validIdx.map { dif[$0]! }
            let deaCompact = ema(compact, period: signal)
            for (j, idx) in validIdx.enumerated() { dea[idx] = deaCompact[j] }
        }
        // 柱 = 2 × (DIF − DEA)（国内软件惯例）
        var hist = [Double?](repeating: nil, count: n)
        for i in 0..<n {
            if let d = dif[i], let s = dea[i] { hist[i] = (d - s) * 2 }
        }
        return (dif, dea, hist)
    }

    // MARK: - KDJ（9, 3, 3）

    public static func kdj(
        highs: [Double], lows: [Double], closes: [Double], period: Int = 9
    ) -> (k: [Double?], d: [Double?], j: [Double?]) {
        let n = closes.count
        var k = [Double?](repeating: nil, count: n)
        var d = [Double?](repeating: nil, count: n)
        var j = [Double?](repeating: nil, count: n)
        guard period > 0, n >= period, highs.count == n, lows.count == n else { return (k, d, j) }
        var prevK = 50.0, prevD = 50.0
        for i in (period - 1)..<n {
            let hh = highs[(i - period + 1)...i].max() ?? 0
            let ll = lows[(i - period + 1)...i].min() ?? 0
            let rsv = hh > ll ? (closes[i] - ll) / (hh - ll) * 100 : 50
            prevK = prevK * 2 / 3 + rsv / 3
            prevD = prevD * 2 / 3 + prevK / 3
            k[i] = prevK
            d[i] = prevD
            j[i] = 3 * prevK - 2 * prevD
        }
        return (k, d, j)
    }

    // MARK: - RSI（Wilder 平滑）

    public static func rsi(_ closes: [Double], period: Int) -> [Double?] {
        let n = closes.count
        var out = [Double?](repeating: nil, count: n)
        guard period > 0, n > period else { return out }
        var gain = 0.0, loss = 0.0
        for i in 1...period {
            let diff = closes[i] - closes[i - 1]
            if diff > 0 { gain += diff } else { loss -= diff }
        }
        var avgGain = gain / Double(period)
        var avgLoss = loss / Double(period)
        out[period] = avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss)
        for i in (period + 1)..<n {
            let diff = closes[i] - closes[i - 1]
            let g = max(diff, 0)
            let l = max(-diff, 0)
            avgGain = (avgGain * Double(period - 1) + g) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + l) / Double(period)
            out[i] = avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss)
        }
        return out
    }

    // MARK: - BOLL（20, 2）

    public static func boll(
        _ closes: [Double], period: Int = 20, multiplier: Double = 2
    ) -> (upper: [Double?], mid: [Double?], lower: [Double?]) {
        let n = closes.count
        let mid = sma(closes, period: period)
        var upper = [Double?](repeating: nil, count: n)
        var lower = [Double?](repeating: nil, count: n)
        guard period > 0, n >= period else { return (upper, mid, lower) }
        for i in (period - 1)..<n {
            guard let m = mid[i] else { continue }
            var varSum = 0.0
            for j in (i - period + 1)...i {
                let x = closes[j] - m
                varSum += x * x
            }
            let sd = (varSum / Double(period)).squareRoot()
            upper[i] = m + sd * multiplier
            lower[i] = m - sd * multiplier
        }
        return (upper, mid, lower)
    }
}

// MARK: - 指标图元（跨平台语义，UI 层自行配色）

/// 主图叠加指标
public enum MainOverlay: String, Sendable, CaseIterable, Hashable {
    case ma, ema, boll
    public var label: String { rawValue.uppercased() }
}

/// 副图指标
public enum SubIndicator: String, Sendable, CaseIterable, Hashable {
    case vol, macd, kdj, rsi
    public var label: String { rawValue.uppercased() }

    /// 副图标题（含参数）
    public var displayName: String {
        switch self {
        case .vol: return "VOL"
        case .macd: return "MACD(12,26,9)"
        case .kdj: return "KDJ(9,3,3)"
        case .rsi: return "RSI(6,12,24)"
        }
    }
}

/// 一条指标线（与 bar 按下标对齐）
public struct IndicatorLine: Sendable, Hashable {
    public let name: String
    public let values: [Double?]

    public init(name: String, values: [Double?]) {
        self.name = name
        self.values = values
    }
}

/// 副图指标数据：若干线 + 可选柱状（MACD）+ 是否以 0 为轴
public struct SubIndicatorData: Sendable {
    public let lines: [IndicatorLine]
    public let histogram: [Double?]?
    public let zeroCentered: Bool

    public init(lines: [IndicatorLine], histogram: [Double?]? = nil, zeroCentered: Bool = false) {
        self.lines = lines
        self.histogram = histogram
        self.zeroCentered = zeroCentered
    }
}
