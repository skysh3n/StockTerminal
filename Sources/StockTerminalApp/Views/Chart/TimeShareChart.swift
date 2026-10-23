import SwiftUI
import TradingCore

/// 分时图渲染数据：价格线 + 累计均价线 + 对称价格区间（围绕昨收）
struct TimeShareRenderData {
    let bars: [KLine]
    let avg: [Double]        // 每分钟累计均价
    let preClose: Double
    let priceMin: Double
    let priceMax: Double
    let volMax: Double

    static func build(bars: [KLine], preClose: Decimal?) -> TimeShareRenderData {
        let fallback = bars.first?.open ?? Decimal(1)
        let pre = max((preClose ?? fallback).doubleValue, 0.01)
        guard !bars.isEmpty else {
            return .init(bars: [], avg: [], preClose: pre,
                         priceMin: pre * 0.99, priceMax: pre * 1.01, volMax: 1)
        }
        var avg: [Double] = []
        avg.reserveCapacity(bars.count)
        var cumVol = 0.0, cumAmt = 0.0
        var hi = -Double.greatestFiniteMagnitude
        var lo = Double.greatestFiniteMagnitude
        var volMax = 1.0
        for b in bars {
            cumVol += Double(b.volume)
            cumAmt += b.turnover.doubleValue
            avg.append(cumVol > 0 ? cumAmt / cumVol : b.close.doubleValue)
            hi = max(hi, b.high.doubleValue)
            lo = min(lo, b.low.doubleValue)
            volMax = max(volMax, Double(b.volume))
        }
        let dev = max(abs(hi - pre), abs(pre - lo), pre * 0.003)
        return .init(bars: bars, avg: avg, preClose: pre,
                     priceMin: pre - dev * 1.12, priceMax: pre + dev * 1.12, volMax: volMax)
    }
}

/// 分时图布局：A 股默认 240 分钟槽；全球指数可按实际分钟数铺满，底部为分时量。
struct TimeShareLayout {
    let size: CGSize
    let data: TimeShareRenderData
    /// 横轴槽位数；A 股固定 240，全球指数用实际 bar 数。
    let slots: Int
    let volHeight: CGFloat

    static let rightMargin: CGFloat = 68
    static let bottomMargin: CGFloat = 18
    static let topMargin: CGFloat = 10
    static let defaultVolHeight: CGFloat = 46
    static let defaultSlots = 240

    init(size: CGSize, data: TimeShareRenderData, slots: Int = Self.defaultSlots, volHeight: CGFloat = Self.defaultVolHeight) {
        self.size = size
        self.data = data
        self.slots = max(slots, 2)
        self.volHeight = volHeight
    }

    var plotWidth: CGFloat { max(size.width - Self.rightMargin, 10) }
    var priceBottom: CGFloat { size.height - Self.bottomMargin - volHeight - 8 }
    var priceHeight: CGFloat { max(priceBottom - Self.topMargin, 10) }

    func x(_ i: Int) -> CGFloat { plotWidth * CGFloat(i) / CGFloat(slots - 1) }

    func y(_ p: Double) -> CGFloat {
        let t = (p - data.priceMin) / max(data.priceMax - data.priceMin, 1e-9)
        return Self.topMargin + priceHeight * (1 - CGFloat(t))
    }

    func index(x: CGFloat) -> Int {
        min(max(Int((x / plotWidth) * CGFloat(slots - 1)), 0), slots - 1)
    }

    func price(y: CGFloat) -> Double {
        let t = 1 - (y - Self.topMargin) / max(priceHeight, 1)
        return data.priceMin + Double(t) * (data.priceMax - data.priceMin)
    }
}

/// 分时图主画布：昨收基准线 + 价格线(渐变填充) + 均价线 + 成交量带 + 双轴（右价格/左百分比）
struct TimeShareCanvas: View {
    let data: TimeShareRenderData
    let layout: TimeShareLayout

    var body: some View {
        Canvas { ctx, size in
            drawGrid(ctx: ctx, size: size)
            drawPreCloseLine(ctx: ctx, size: size)
            guard data.bars.count >= 2 else { return }
            drawVolume(ctx: ctx, size: size)
            drawPriceArea(ctx: ctx)
            drawAvgLine(ctx: ctx)
            drawLastDot(ctx: ctx)
        }
    }

    private func drawGrid(ctx: GraphicsContext, size: CGSize) {
        // 横向 4 等分 + 价格/百分比双轴标签
        for k in 0...4 {
            let p = data.priceMin + (data.priceMax - data.priceMin) * Double(k) / 4
            let y = layout.y(p)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width - TimeShareLayout.rightMargin, y: y))
            ctx.stroke(line, with: .color(Color.dsBorder.opacity(k == 2 ? 0.6 : 0.3)), lineWidth: 0.5)

            let color = p > data.preClose ? Sem.up : p < data.preClose ? Sem.down : Sem.flat
            ctx.draw(Text(String(format: "%.2f", p)).font(.system(size: 9.5, weight: .regular).monospacedDigit()).tracking(0.2).foregroundColor(color),
                     at: CGPoint(x: size.width - TimeShareLayout.rightMargin / 2, y: y), anchor: .center)
            let pct = (p - data.preClose) / data.preClose * 100
            ctx.draw(Text(String(format: "%+.1f%%", pct)).font(.system(size: 9.5, weight: .regular).monospacedDigit()).foregroundColor(color.opacity(0.7)),
                     at: CGPoint(x: 24, y: y), anchor: .center)
        }
        // 纵向时段刻度：A 股固定五段；按 bar 铺满时取首尾与等分点的实际时间。
        let labels: [(Int, String)] = {
            if layout.slots == TimeShareLayout.defaultSlots {
                return [(0, "09:30"), (60, "10:30"), (120, "11:30"), (180, "14:00"), (239, "15:00")]
            }
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            let last = layout.slots - 1
            let marks = [0, last / 4, last / 2, last * 3 / 4, last]
            return marks.map { i in
                let text: String
                if i < data.bars.count {
                    text = f.string(from: data.bars[i].timestamp)
                } else {
                    text = ""
                }
                return (i, text)
            }
        }()
        for (slot, text) in labels {
            let x = layout.x(min(slot, layout.slots - 1))
            var line = Path()
            line.move(to: CGPoint(x: x, y: TimeShareLayout.topMargin))
            line.addLine(to: CGPoint(x: x, y: size.height - TimeShareLayout.bottomMargin))
            ctx.stroke(line, with: .color(Color.dsBorder.opacity(0.22)), lineWidth: 0.5)
            if !text.isEmpty {
                ctx.draw(Text(text).font(.system(size: 9.5, weight: .regular).monospacedDigit()).tracking(0.2).foregroundColor(Color.dsTextTertiary),
                         at: CGPoint(x: min(max(x, 20), size.width - TimeShareLayout.rightMargin - 20),
                                     y: size.height - TimeShareLayout.bottomMargin / 2), anchor: .center)
            }
        }
        // 右轴线
        var axis = Path()
        axis.move(to: CGPoint(x: size.width - TimeShareLayout.rightMargin, y: 0))
        axis.addLine(to: CGPoint(x: size.width - TimeShareLayout.rightMargin, y: size.height - TimeShareLayout.bottomMargin))
        ctx.stroke(axis, with: .color(Color.dsBorder), lineWidth: 0.5)
    }

    private func drawPreCloseLine(ctx: GraphicsContext, size: CGSize) {
        let y = layout.y(data.preClose)
        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: size.width - TimeShareLayout.rightMargin, y: y))
        ctx.stroke(line, with: .color(Color.dsTextTertiary.opacity(0.55)),
                   style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
    }

    private func pricePath() -> Path {
        var path = Path()
        for (i, b) in data.bars.enumerated() {
            let pt = CGPoint(x: layout.x(i), y: layout.y(b.close.doubleValue))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }

    private func drawPriceArea(ctx: GraphicsContext) {
        let line = pricePath()
        // 渐变填充（价格线 → 底部）
        var area = line
        if let lastX = data.bars.indices.last.map({ layout.x($0) }) {
            area.addLine(to: CGPoint(x: lastX, y: layout.priceBottom))
            area.addLine(to: CGPoint(x: layout.x(0), y: layout.priceBottom))
            area.closeSubpath()
        }
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [Color.dsInfo.opacity(0.16), Color.dsInfo.opacity(0.01)]),
            startPoint: CGPoint(x: 0, y: TimeShareLayout.topMargin),
            endPoint: CGPoint(x: 0, y: layout.priceBottom)
        ))
        ctx.stroke(line, with: .color(Color(.sRGB, red: 0.55, green: 0.73, blue: 1.0)), lineWidth: 1.2)
    }

    private func drawAvgLine(ctx: GraphicsContext) {
        var path = Path()
        for (i, v) in data.avg.enumerated() {
            let pt = CGPoint(x: layout.x(i), y: layout.y(v))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(Color.dsAccent.opacity(0.9)), lineWidth: 0.9)
    }

    private func drawLastDot(ctx: GraphicsContext) {
        guard let last = data.bars.last else { return }
        let pt = CGPoint(x: layout.x(data.bars.count - 1), y: layout.y(last.close.doubleValue))
        let color = last.close.doubleValue >= data.preClose ? Sem.up : Sem.down
        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)),
                 with: .color(color))
        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5.5, y: pt.y - 5.5, width: 11, height: 11)),
                 with: .color(color.opacity(0.25)))
    }

    private func drawVolume(ctx: GraphicsContext, size: CGSize) {
        let baseY = size.height - TimeShareLayout.bottomMargin
        let w = max(layout.plotWidth / CGFloat(layout.slots) * 0.75, 0.8)
        for (i, b) in data.bars.enumerated() {
            guard i < layout.slots else { break }
            let h = CGFloat(Double(b.volume) / data.volMax) * layout.volHeight
            guard h > 0.3 else { continue }
            // 分时量颜色：相对前一分钟涨跌（指数分时 open==close，不能用 isUp）
            let up: Bool = {
                if i == 0 { return b.close.doubleValue >= data.preClose }
                return b.close >= data.bars[i - 1].close
            }()
            let rect = CGRect(x: layout.x(i) - w / 2, y: baseY - h, width: w, height: h)
            ctx.fill(Path(rect), with: .color((up ? Sem.up : Sem.down).opacity(0.75)))
        }
    }
}

/// 分时十字光标层（独立重绘，不牵动主图）
struct TimeShareCrosshair: View {
    let data: TimeShareRenderData
    let layout: TimeShareLayout
    let viewport: Viewport

    var body: some View {
        let hover = viewport.hoverPoint
        Canvas { ctx, size in
            guard let hover, data.bars.count >= 2 else { return }
            let idx = min(layout.index(x: hover.x), data.bars.count - 1)
            let bar = data.bars[idx]
            let x = layout.x(idx)

            var v = Path()
            v.move(to: CGPoint(x: x, y: TimeShareLayout.topMargin))
            v.addLine(to: CGPoint(x: x, y: size.height - TimeShareLayout.bottomMargin))
            ctx.stroke(v, with: .color(Color.dsTextSecondary.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))

            let hy = min(max(hover.y, TimeShareLayout.topMargin), layout.priceBottom)
            var h = Path()
            h.move(to: CGPoint(x: 0, y: hy))
            h.addLine(to: CGPoint(x: size.width - TimeShareLayout.rightMargin, y: hy))
            ctx.stroke(h, with: .color(Color.dsTextSecondary.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))

            // 右轴价格标签
            let p = layout.price(y: hy)
            let color = p > data.preClose ? Sem.up : p < data.preClose ? Sem.down : Sem.flat
            let rect = CGRect(x: size.width - TimeShareLayout.rightMargin + 3, y: hy - 8.5,
                              width: TimeShareLayout.rightMargin - 6, height: 17)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color))
            ctx.draw(Text(String(format: "%.2f", p)).font(.system(size: 9.5, weight: .semibold).monospacedDigit()).foregroundColor(.white),
                     at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)

            // 信息框：时间 / 价格 / 均价 / 涨跌 / 量
            let close = bar.close.doubleValue
            let pct = (close - data.preClose) / data.preClose * 100
            let upColor = pct >= 0 ? Sem.up : Sem.down
            var attr = AttributedString()
            let parts: [(String, Color)] = [
                (Fmt.minute(bar.timestamp) + "\n", .dsTextSecondary),
                ("价格 ", .dsTextTertiary), (String(format: "%.2f", close), upColor),
                ("  均价 ", .dsTextTertiary),
                (String(format: "%.2f", idx < data.avg.count ? data.avg[idx] : close), .dsAccent),
                ("\n涨跌 ", .dsTextTertiary), (String(format: "%+.2f%%", pct), upColor),
                ("  量 ", .dsTextTertiary), (Fmt.volume(shares: bar.volume), .dsTextSecondary),
            ]
            for (text, c) in parts {
                var s = AttributedString(text)
                s.foregroundColor = c
                s.font = .system(size: 10, weight: .medium).monospacedDigit()
                attr += s
            }
            let boxRect = CGRect(x: 6, y: 4, width: 190, height: 48)
            ctx.fill(Path(roundedRect: boxRect, cornerRadius: 6), with: .color(Color.dsElevated.opacity(0.88)))
            ctx.stroke(Path(roundedRect: boxRect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: 5.8), with: .color(Color.dsBorderStrong.opacity(0.6)), lineWidth: 0.6)
            ctx.draw(Text(attr), at: CGPoint(x: 14, y: 9), anchor: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

/// 分时图容器（悬停交互；分时不支持缩放平移——A股惯例固定 240 分钟）
struct TimeShareChartView: View {
    let series: KLineSeries
    let viewport: Viewport
    /// `true`：横轴按实际分钟数铺满（全球指数），并加高分时量区域。
    var fitBarsToWidth: Bool = false

    var body: some View {
        GeometryReader { geo in
            let bars = series.bars
            let data = TimeShareRenderData.build(bars: bars, preClose: series.preClose)
            let slots = fitBarsToWidth ? max(bars.count, 2) : TimeShareLayout.defaultSlots
            let volH: CGFloat = fitBarsToWidth ? 64 : TimeShareLayout.defaultVolHeight
            let layout = TimeShareLayout(size: geo.size, data: data, slots: slots, volHeight: volH)
            ZStack {
                Color.clear
                TimeShareCanvas(data: data, layout: layout)
                TimeShareCrosshair(data: data, layout: layout, viewport: viewport)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): viewport.hoverPoint = p
                case .ended: viewport.hoverPoint = nil
                }
            }
        }
    }
}
