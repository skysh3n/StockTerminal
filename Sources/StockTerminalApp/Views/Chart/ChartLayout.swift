import Foundation
import SwiftUI
import TradingCore

/// 图表坐标映射（纯函数结构）：index ↔ x、price ↔ y。
/// 主图/副图/光标层共用同一份 layout 实例，保证像素级对齐。
struct ChartLayout {
    let size: CGSize
    let visible: Range<Int>       // 可见 bar 索引区间
    let priceMin: Double
    let priceMax: Double
    let candleSpacing: CGFloat
    let rightMargin: CGFloat
    let bottomMargin: CGFloat
    let topMargin: CGFloat

    static let defaultRightMargin: CGFloat = 68
    static let defaultBottomMargin: CGFloat = 18
    static let defaultTopMargin: CGFloat = 10

    var plotWidth: CGFloat { max(size.width - rightMargin, 10) }
    var plotHeight: CGFloat { max(size.height - topMargin - bottomMargin, 10) }

    init(
        size: CGSize,
        bars: [KLine],
        visibleCount: Int,
        offsetFromEnd: Int,
        rightMargin: CGFloat = ChartLayout.defaultRightMargin,
        bottomMargin: CGFloat = ChartLayout.defaultBottomMargin,
        topMargin: CGFloat = ChartLayout.defaultTopMargin,
        verticalPadding: Double = 0.06
    ) {
        self.size = size
        self.rightMargin = rightMargin
        self.bottomMargin = bottomMargin
        self.topMargin = topMargin

        let count = bars.count
        guard count > 0 else {
            self.visible = 0..<0
            self.candleSpacing = 8
            self.priceMin = 0
            self.priceMax = 1
            return
        }
        let vc = max(10, min(visibleCount, max(count, 10)))
        let upper = min(count, max(1, count - offsetFromEnd))
        let lower = max(0, upper - vc)
        self.visible = lower..<upper
        self.candleSpacing = (size.width - rightMargin) / CGFloat(max(visible.count, 1))

        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for i in visible.lowerBound..<min(visible.upperBound, count) {
            lo = min(lo, bars[i].low.doubleValue)
            hi = max(hi, bars[i].high.doubleValue)
        }
        if lo >= hi { lo -= 1; hi += 1 }
        let span = hi - lo
        self.priceMin = lo - span * verticalPadding
        self.priceMax = hi + span * verticalPadding
    }

    /// bar 索引 → x 像素（蜡烛中心）
    func x(index: Int) -> CGFloat {
        (CGFloat(index - visible.lowerBound) + 0.5) * candleSpacing
    }

    /// 价格 → y 像素
    func y(price: Double) -> CGFloat {
        let t = (price - priceMin) / max(priceMax - priceMin, 1e-9)
        return topMargin + plotHeight * (1 - CGFloat(t))
    }

    /// x 像素 → bar 索引（可能越界，调用方自行 clamp）
    func index(x: CGFloat) -> Int {
        visible.lowerBound + Int(x / max(candleSpacing, 0.5))
    }

    /// y 像素 → 价格
    func price(y: CGFloat) -> Double {
        let t = 1 - (y - topMargin) / max(plotHeight, 1)
        return priceMin + Double(t) * (priceMax - priceMin)
    }

    /// 「好看」的网格步长（1/2/5 × 10^n）
    static func niceStep(range: Double, targetLines: Int = 5) -> Double {
        guard range > 0 else { return 1 }
        let raw = range / Double(max(targetLines, 1))
        let mag = pow(10, floor(log10(raw)))
        let norm = raw / mag
        let step: Double
        switch norm {
        case ..<1.5: step = 1
        case ..<3: step = 2
        case ..<7: step = 5
        default: step = 10
        }
        return step * mag
    }
}
