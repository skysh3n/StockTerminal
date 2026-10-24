import SwiftUI
import TradingCore

/// 主图叠加线（带 UI 颜色）
struct ChartLine {
    let name: String
    let color: Color
    let values: [Double?]
}

/// 蜡烛主图：网格 + 蜡烛 + 叠加指标线（MA/EMA/BOLL）+ 坐标轴 + 最新价标签。
/// 全部输入为纯值（bars/lines/layout 由父级 body 读取后传入）——
/// Observation 依赖登记发生在父级，Canvas 闭包保持纯函数，数据驱动重绘。
struct CandlestickCanvas: View {
    let bars: [KLine]
    let lines: [ChartLine]
    let srLevels: [SRLevel]
    let layout: ChartLayout
    let preClose: Double?
    let tf: TimeFrame
    /// 用户画线：水平价位（主图坐标）。
    var hLines: [Double] = []

    var body: some View {
        Canvas { ctx, size in
            guard !bars.isEmpty, layout.visible.count > 0 else { return }
            drawGrid(ctx: ctx, size: size)
            drawSRLevels(ctx: ctx, size: size)
            drawUserHLines(ctx: ctx, size: size)
            drawLastPriceLine(ctx: ctx, size: size)
            drawCandles(ctx: ctx)
            drawOverlayLines(ctx: ctx)
            drawAxes(ctx: ctx, size: size)
            drawLegend(ctx: ctx)
        }
    }

    private func drawUserHLines(ctx: GraphicsContext, size: CGSize) {
        let plotBottom = size.height - layout.bottomMargin
        for price in hLines {
            let y = layout.y(price: price)
            guard y > layout.topMargin, y < plotBottom else { continue }
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width - layout.rightMargin, y: y))
            ctx.stroke(line, with: .color(Color.dsAccent.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
            let label = String(format: "%.2f", price)
            let tag = CGRect(x: 4, y: y - 7, width: CGFloat(label.count) * 6.2 + 8, height: 14)
            ctx.fill(Path(roundedRect: tag, cornerRadius: 3), with: .color(Color.dsAccent.opacity(0.18)))
            ctx.draw(
                Text(label).font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundColor(Color.dsAccent),
                at: CGPoint(x: tag.minX + 4, y: tag.midY), anchor: .leading
            )
        }
    }

    // MARK: - 支撑压力线

    private func drawSRLevels(ctx: GraphicsContext, size: CGSize) {
        guard !srLevels.isEmpty else { return }
        let plotBottom = size.height - layout.bottomMargin
        // 按 y 排序后若标签间距不足 15pt 则下移错位，保证多条压力/支撑靠近时都清晰可读
        var lastLabelBottom: CGFloat = -100
        for level in srLevels.sorted(by: { layout.y(price: $0.price) < layout.y(price: $1.price) }) {
            let y = layout.y(price: level.price)
            guard y > layout.topMargin, y < plotBottom else { continue }
            let isResistance = level.kind == .resistance
            let color = isResistance ? Sem.up : Sem.down
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width - layout.rightMargin, y: y))
            ctx.stroke(
                line, with: .color(color.opacity(0.38)),
                style: StrokeStyle(lineWidth: level.touches >= 3 ? 1.1 : 0.8, dash: [4, 3])
            )
            // 标签：绘图区右缘半透明底签（避开左上 MA 图例与十字光标信息框，盖住网格/蜡烛也清晰可读）
            let label = (isResistance ? "压力 " : "支撑 ")
                + String(format: "%.2f", level.price)
                + (level.touches > 1 ? " ×\(level.touches)" : "")
            let labelW = CGFloat(label.count) * 6.0 + 10
            var labelY = y - 7
            if labelY < lastLabelBottom + 1 { labelY = lastLabelBottom + 1 }
            labelY = min(labelY, plotBottom - 15)
            lastLabelBottom = labelY + 14
            let tagRect = CGRect(x: size.width - layout.rightMargin - labelW - 3,
                                 y: labelY, width: labelW, height: 14)
            ctx.fill(Path(roundedRect: tagRect, cornerRadius: 3),
                     with: .color(Color.dsBgBase.opacity(0.78)))
            ctx.stroke(Path(roundedRect: tagRect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: 2.8),
                       with: .color(color.opacity(0.35)), lineWidth: 0.6)
            ctx.draw(
                Text(label)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .tracking(0.2)
                    .foregroundColor(color.opacity(0.95)),
                at: CGPoint(x: tagRect.minX + 5, y: tagRect.midY), anchor: .leading
            )
        }
    }

    // MARK: - 网格

    private func drawGrid(ctx: GraphicsContext, size: CGSize) {
        let step = ChartLayout.niceStep(range: layout.priceMax - layout.priceMin)
        var p = ceil(layout.priceMin / step) * step
        while p <= layout.priceMax {
            let y = layout.y(price: p)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width - layout.rightMargin, y: y))
            ctx.stroke(line, with: .color(Color.dsBorder.opacity(0.22)), lineWidth: 0.5)
            p += step
        }
        let barStep = max(1, layout.visible.count / 6)
        var i = layout.visible.lowerBound + barStep / 2
        let upper = min(layout.visible.upperBound, bars.count)
        while i < upper {
            let x = layout.x(index: i)
            var line = Path()
            line.move(to: CGPoint(x: x, y: layout.topMargin))
            line.addLine(to: CGPoint(x: x, y: size.height - layout.bottomMargin))
            ctx.stroke(line, with: .color(Color.dsBorder.opacity(0.22)), lineWidth: 0.5)
            i += barStep
        }
    }

    // MARK: - 蜡烛（批量 Path：涨/跌各一条影线路径 + 一个实体路径）

    private func drawCandles(ctx: GraphicsContext) {
        let bodyWidth = max(layout.candleSpacing * 0.7, 1)
        let upper = min(layout.visible.upperBound, bars.count)
        var wickUp = Path(), wickDown = Path(), bodyUp = Path(), bodyDown = Path()
        for i in layout.visible.lowerBound..<upper {
            let b = bars[i]
            let x = layout.x(index: i)
            let o = b.open.doubleValue
            let c = b.close.doubleValue
            let yH = layout.y(price: b.high.doubleValue)
            let yL = layout.y(price: b.low.doubleValue)
            let yo = layout.y(price: o)
            let yc = layout.y(price: c)
            let rect = CGRect(
                x: x - bodyWidth / 2, y: min(yo, yc),
                width: bodyWidth, height: max(abs(yo - yc), 1)
            )
            if c >= o {
                wickUp.move(to: CGPoint(x: x, y: yH))
                wickUp.addLine(to: CGPoint(x: x, y: yL))
                bodyUp.addRect(rect)
            } else {
                wickDown.move(to: CGPoint(x: x, y: yH))
                wickDown.addLine(to: CGPoint(x: x, y: yL))
                bodyDown.addRect(rect)
            }
        }
        ctx.stroke(wickUp, with: .color(Sem.up), lineWidth: 1)
        ctx.stroke(wickDown, with: .color(Sem.down), lineWidth: 1)
        ctx.fill(bodyUp, with: .color(Sem.up))
        ctx.fill(bodyDown, with: .color(Sem.down))
    }

    // MARK: - 叠加指标线

    private func drawOverlayLines(ctx: GraphicsContext) {
        let upper = min(layout.visible.upperBound, bars.count)
        for line in lines {
            var path = Path()
            var started = false
            for i in layout.visible.lowerBound..<upper where i < line.values.count {
                guard let v = line.values[i] else { started = false; continue }
                let pt = CGPoint(x: layout.x(index: i), y: layout.y(price: v))
                if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
            }
            ctx.stroke(path, with: .color(line.color), lineWidth: 1)
        }
    }

    // MARK: - 坐标轴

    private func drawAxes(ctx: GraphicsContext, size: CGSize) {
        let step = ChartLayout.niceStep(range: layout.priceMax - layout.priceMin)
        var p = ceil(layout.priceMin / step) * step
        let axisX = size.width - layout.rightMargin / 2
        while p <= layout.priceMax {
            ctx.draw(
                Text(String(format: "%.2f", p))
                    .font(.system(size: 9.5, weight: .regular).monospacedDigit())
                    .tracking(0.2)
                    .foregroundColor(Color.dsTextTertiary),
                at: CGPoint(x: axisX, y: layout.y(price: p)), anchor: .center
            )
            p += step
        }
        var axis = Path()
        axis.move(to: CGPoint(x: size.width - layout.rightMargin, y: 0))
        axis.addLine(to: CGPoint(x: size.width - layout.rightMargin, y: size.height - layout.bottomMargin))
        ctx.stroke(axis, with: .color(Color.dsBorder.opacity(0.8)), lineWidth: 0.5)

        let barStep = max(1, layout.visible.count / 6)
        var i = layout.visible.lowerBound + barStep / 2
        let upper = min(layout.visible.upperBound, bars.count)
        while i < upper {
            ctx.draw(
                Text(Fmt.chartTime(bars[i].timestamp, tf: tf))
                    .font(.system(size: 9.5, weight: .regular).monospacedDigit())
                    .tracking(0.2)
                    .foregroundColor(Color.dsTextTertiary),
                at: CGPoint(x: layout.x(index: i), y: size.height - layout.bottomMargin / 2), anchor: .center
            )
            i += barStep
        }
    }

    // MARK: - 最新价

    private func drawLastPriceLine(ctx: GraphicsContext, size: CGSize) {
        guard let lastBar = bars.last, layout.visible.count > 0 else { return }
        guard layout.visible.upperBound >= bars.count else { return }
        let lastP = lastBar.close.doubleValue
        let ref = preClose ?? lastBar.open.doubleValue
        let color = lastP > ref ? Sem.up : lastP < ref ? Sem.down : Sem.flat
        let y = layout.y(price: lastP)
        guard y > 0, y < size.height - layout.bottomMargin else { return }

        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: size.width - layout.rightMargin, y: y))
        ctx.stroke(line, with: .color(color.opacity(0.55)),
                   style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

        let tagW = layout.rightMargin - 6
        let rect = CGRect(x: size.width - layout.rightMargin + 3, y: y - 8.5, width: tagW, height: 17)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color))
        ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: 3.8),
                   with: .color(.white.opacity(0.18)), lineWidth: 0.6)
        ctx.draw(
            Text(String(format: "%.2f", lastP))
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .tracking(0.2)
                .foregroundColor(.white),
            at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center
        )
    }

    // MARK: - 叠加线图例（左上角）

    private func drawLegend(ctx: GraphicsContext) {
        let upper = min(layout.visible.upperBound, bars.count)
        guard upper > layout.visible.lowerBound else { return }
        let idx = upper - 1
        var attr = AttributedString()
        for line in lines {
            var name = AttributedString(line.name + ": ")
            name.foregroundColor = line.color
            name.font = .system(size: 9.5, weight: .medium).monospacedDigit()
            attr += name
            let value = (idx < line.values.count) ? line.values[idx] : nil
            var val = AttributedString((value.map { String(format: "%.2f  ", $0) } ?? "--  "))
            val.foregroundColor = line.color
            val.font = .system(size: 9.5, weight: .medium).monospacedDigit()
            attr += val
        }
        ctx.draw(Text(attr), at: CGPoint(x: 8, y: 4), anchor: .topLeading)
    }
}

/// 成交量副图（与主图共用 viewport，列对齐）
/// 十字星悬停时图例显示该根成交量；无悬停显示可见区最后一根。
struct VolumePane: View {
    let bars: [KLine]
    let layout: ChartLayout
    var hover: CGPoint? = nil

    var body: some View {
        Canvas { ctx, size in
            guard !bars.isEmpty, layout.visible.count > 0 else { return }
            let lo = layout.visible.lowerBound
            let upper = min(layout.visible.upperBound, bars.count)
            guard upper > lo else { return }
            var volMax = 1.0
            for i in lo..<upper {
                volMax = max(volMax, Double(bars[i].volume))
            }
            let plotH = size.height - 6
            let bodyWidth = max(layout.candleSpacing * 0.7, 1)
            var upPath = Path(), downPath = Path()
            for i in lo..<upper {
                let b = bars[i]
                let h = CGFloat(Double(b.volume) / volMax) * plotH
                guard h > 0.3 else { continue }
                let rect = CGRect(x: layout.x(index: i) - bodyWidth / 2, y: size.height - h,
                                  width: bodyWidth, height: h)
                if b.isUp { upPath.addRect(rect) } else { downPath.addRect(rect) }
            }
            ctx.fill(upPath, with: .color(Sem.up.opacity(0.8)))
            ctx.fill(downPath, with: .color(Sem.down.opacity(0.8)))

            let focusIdx = IndicatorPane.focusIndex(hover: hover, layout: layout, lower: lo, upper: upper)
            if hover != nil {
                let x = layout.x(index: focusIdx)
                var vline = Path()
                vline.move(to: CGPoint(x: x, y: 0))
                vline.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(vline, with: .color(Color.dsTextSecondary.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
            }
            let bar = bars[focusIdx]
            let volColor = bar.isUp ? Sem.up : Sem.down
            var attr = AttributedString("VOL  ")
            attr.foregroundColor = Color.dsTextTertiary
            attr.font = .system(size: 9.5, weight: .medium).monospacedDigit()
            var val = AttributedString(Fmt.volume(shares: bar.volume))
            val.foregroundColor = volColor
            val.font = .system(size: 9.5, weight: .semibold).monospacedDigit()
            attr += val
            ctx.draw(Text(attr), at: CGPoint(x: 8, y: 2), anchor: .topLeading)
        }
    }
}
