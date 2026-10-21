import Foundation

/// 支撑 / 压力位
public enum SRKind: String, Sendable, Hashable {
    case resistance   // 压力（现价上方）
    case support      // 支撑（现价下方）
}

public struct SRLevel: Sendable, Hashable {
    public let price: Double
    public let kind: SRKind
    /// 聚类合并的触及次数（越多越有效，UI 加粗并标注 ×N）
    public let touches: Int

    public init(price: Double, kind: SRKind, touches: Int) {
        self.price = price
        self.kind = kind
        self.touches = touches
    }
}

/// 支撑压力识别：
/// 1) 分形法找摆动高点/低点（窗口 ±fractal 根，右窗口不完整的最新 bar 不参与）
/// 2) 相对最新收盘价分类：上方的摆动高点 = 压力，下方的摆动低点 = 支撑
/// 3) 按距离由近到远聚类（同价位 ±tolerance 合并，累计触及次数）
/// 4) 每侧取最近的 maxPerSide 个
public enum SupportResistance {

    public static func levels(
        bars: [KLine],
        lookback: Int = 260,
        fractal: Int = 3,
        maxPerSide: Int = 2,
        tolerance: Double = 0.005
    ) -> [SRLevel] {
        let n = bars.count
        guard n > fractal * 2 + 1, let lastBar = bars.last else { return [] }
        let last = lastBar.close.doubleValue
        guard last > 0 else { return [] }

        let start = max(fractal, n - lookback)
        let end = n - fractal   // 右窗口不完整的 bar 不判定为摆动点
        guard end > start else { return [] }

        var swingHighs: [(price: Double, index: Int)] = []
        var swingLows: [(price: Double, index: Int)] = []

        for i in start..<end {
            let hi = bars[i].high.doubleValue
            let lo = bars[i].low.doubleValue
            var isHigh = true
            var isLow = true
            // 左窗口要求严格更高/更低：横盘平台（等值序列）只认第一根，避免把平台当摆动点
            for j in (i - fractal)..<i {
                if bars[j].high.doubleValue >= hi { isHigh = false }
                if bars[j].low.doubleValue <= lo { isLow = false }
                if !isHigh && !isLow { break }
            }
            guard isHigh || isLow else { continue }
            // 右窗口允许等值（右端不完整，等值出现在右端不影响"已确认"的摆动）
            if isHigh {
                for j in (i + 1)...(i + fractal) where bars[j].high.doubleValue > hi {
                    isHigh = false
                    break
                }
            }
            if isLow {
                for j in (i + 1)...(i + fractal) where bars[j].low.doubleValue < lo {
                    isLow = false
                    break
                }
            }
            if isHigh { swingHighs.append((hi, i)) }
            if isLow { swingLows.append((lo, i)) }
        }

        // 相对现价分类，并按距离由近到远排序
        let resistancePoints = swingHighs.filter { $0.price > last }.sorted { $0.price < $1.price }
        let supportPoints = swingLows.filter { $0.price < last }.sorted { $0.price > $1.price }

        let resistances = cluster(resistancePoints, kind: .resistance, tolerance: tolerance, limit: maxPerSide)
        let supports = cluster(supportPoints, kind: .support, tolerance: tolerance, limit: maxPerSide)
        return resistances + supports
    }

    /// 价格聚类：输入已按距离排序，取最近的簇代表，簇内合并并累计触及次数
    private static func cluster(
        _ points: [(price: Double, index: Int)],
        kind: SRKind,
        tolerance: Double,
        limit: Int
    ) -> [SRLevel] {
        guard !points.isEmpty else { return [] }
        var clusters: [(price: Double, touches: Int)] = []
        for p in points {
            if let idx = clusters.firstIndex(where: {
                abs($0.price - p.price) / max(p.price, 1e-9) <= tolerance
            }) {
                clusters[idx].touches += 1
            } else {
                clusters.append((p.price, 1))
            }
            if clusters.count >= limit { break }
        }
        return clusters.map { SRLevel(price: $0.price, kind: kind, touches: $0.touches) }
    }
}
