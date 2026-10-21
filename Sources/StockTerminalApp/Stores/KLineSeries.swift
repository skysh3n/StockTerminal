import Foundation
import Observation
import TradingCore

/// 单标的单周期 K 线序列：bars + MA 缓存。
/// 性能核心：流式增量合并——新 tick 只替换/追加尾部 bar，MA 只重算尾部窗口，O(60) 而非全量。
@MainActor
@Observable
final class KLineSeries {
    static let maPeriods = [5, 10, 20, 60]

    let symbol: String
    let timeFrame: TimeFrame
    var id: String { "\(symbol)|\(timeFrame.rawValue)" }

    private(set) var bars: [KLine] = []
    /// MA 值（period → 与 bars 下标对齐；不足周期为 nil），绘图直接取用
    private(set) var ma: [Int: [Double?]] = [:]
    var preClose: Decimal?

    private var closes: [Double] = []

    var isEmpty: Bool { bars.isEmpty }
    var last: KLine? { bars.last }

    init(symbol: String, timeFrame: TimeFrame) {
        self.symbol = symbol
        self.timeFrame = timeFrame
        for p in Self.maPeriods { ma[p] = [] }
    }

    /// 全量加载（切换标的/周期时）
    func load(_ newBars: [KLine], preClose: Decimal?) {
        bars = newBars
        self.preClose = preClose
        closes = newBars.map { $0.close.doubleValue }
        for p in Self.maPeriods {
            ma[p] = (0..<bars.count).map { maValue(period: p, endIndex: $0) }
        }
    }

    /// 流式合并：同时间戳替换尾 bar，新时间戳追加；旧数据忽略
    func merge(_ bar: KLine) {
        if let lastTs = bars.last?.timestamp {
            if bar.timestamp == lastTs {
                bars[bars.count - 1] = bar
            } else if bar.timestamp > lastTs {
                bars.append(bar)
            } else {
                return
            }
        } else {
            bars = [bar]
        }
        closes = bars.map { $0.close.doubleValue }
        recomputeTailMA()
    }

    /// 只重算受影响的尾部（最长周期 + 余量）
    private func recomputeTailMA() {
        let maxP = Self.maPeriods.max() ?? 60
        let start = max(0, bars.count - (maxP + 2))
        for p in Self.maPeriods {
            var arr = ma[p] ?? []
            if arr.count < bars.count {
                arr.append(contentsOf: Array<Double?>(repeating: nil, count: bars.count - arr.count))
            } else if arr.count > bars.count {
                arr.removeLast(arr.count - bars.count)
            }
            for i in start..<bars.count {
                arr[i] = maValue(period: p, endIndex: i)
            }
            ma[p] = arr
        }
    }

    private func maValue(period: Int, endIndex: Int) -> Double? {
        guard endIndex >= period - 1, closes.count > endIndex else { return nil }
        var sum = 0.0
        for i in (endIndex - period + 1)...endIndex { sum += closes[i] }
        return sum / Double(period)
    }

    // MARK: - 技术指标（按需计算：n≤800 且 4Hz 下开销可忽略，不做缓存以免失效逻辑出错）

    /// 主图叠加线（MA/EMA/BOLL）
    func overlayLines(_ kind: MainOverlay) -> [IndicatorLine] {
        let closes = bars.map { $0.close.doubleValue }
        switch kind {
        case .ma:
            return KLineSeries.maPeriods.compactMap { p in
                guard let values = ma[p] else { return nil }
                return IndicatorLine(name: "MA\(p)", values: values)
            }
        case .ema:
            return KLineSeries.maPeriods.map {
                IndicatorLine(name: "EMA\($0)", values: Indicators.ema(closes, period: $0))
            }
        case .boll:
            let b = Indicators.boll(closes)
            return [
                IndicatorLine(name: "UP", values: b.upper),
                IndicatorLine(name: "MID", values: b.mid),
                IndicatorLine(name: "LOW", values: b.lower),
            ]
        }
    }

    /// 副图指标数据（MACD/KDJ/RSI）
    func subIndicatorData(_ kind: SubIndicator) -> SubIndicatorData {
        let closes = bars.map { $0.close.doubleValue }
        switch kind {
        case .vol:
            return SubIndicatorData(lines: [])
        case .macd:
            let m = Indicators.macd(closes)
            return SubIndicatorData(
                lines: [
                    IndicatorLine(name: "DIF", values: m.dif),
                    IndicatorLine(name: "DEA", values: m.dea),
                ],
                histogram: m.hist,
                zeroCentered: true
            )
        case .kdj:
            let k = Indicators.kdj(
                highs: bars.map { $0.high.doubleValue },
                lows: bars.map { $0.low.doubleValue },
                closes: closes
            )
            return SubIndicatorData(lines: [
                IndicatorLine(name: "K", values: k.k),
                IndicatorLine(name: "D", values: k.d),
                IndicatorLine(name: "J", values: k.j),
            ])
        case .rsi:
            return SubIndicatorData(lines: [6, 12, 24].map {
                IndicatorLine(name: "RSI\($0)", values: Indicators.rsi(closes, period: $0))
            })
        }
    }
}
