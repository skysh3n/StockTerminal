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

    var body: some View {
        Canvas { ctx, size in
            guard !bars.isEmpty, layout.visible.count > 0 else { return }
            drawGrid(ctx: ctx, size: size)
            drawCandles(ctx: ctx)
            drawOverlayLines(ctx: ctx)
            // 先画坐标轴刻度，再画价签；价签占用的 Y 带跳过刻度，避免灰字叠在红/绿 pill 上
            drawAxes(ctx: ctx, size: size, skipYs: axisLabelSkipYs())
            drawSRLevels(ctx: ctx, size: size)
            drawLastPriceLine(ctx: ctx, size: size)
            drawLegend(ctx: ctx)
        }
    }

    /// 右侧价格轴上会被最新价 / 支撑压力 pill 盖住的 Y 带（含错位后的标签位置）。
    private func axisLabelSkipYs() -> [ClosedRange<CGFloat>] {
        let half: CGFloat = 10
        var bands: [ClosedRange<CGFloat>] = []
        if let last = bars.last, layout.visible.upperBound >= bars.count {
            let y = layout.y(price: last.close.doubleValue)
            bands.append((y - half)...(y + half))
        }
        for midY in srAxisPillMidYs() {
            bands.append((midY - half)...(midY + half))
        }
        return bands
    }

    /// 支撑压力右侧 pill 的中心 Y（与绘制时相同的错位规则）。
    private func srAxisPillMidYs() -> [CGFloat] {
        guard !srLevels.isEmpty else { return [] }
        let plotBottom = layout.size.height - layout.bottomMargin
        var lastLabelBottom: CGFloat = -100
        var mids: [CGFloat] = []
        for level in srLevels.sorted(by: { layout.y(price: $0.price) < layout.y(price: $1.price) }) {
            let y = layout.y(price: level.price)
            guard y > layout.topMargin, y < plotBottom else { continue }
            var labelY = y - 8.5
            if labelY < lastLabelBottom + 2 { labelY = lastLabelBottom + 2 }
            labelY = min(max(labelY, layout.topMargin), plotBottom - 17)
            lastLabelBottom = labelY + 17
            mids.append(labelY + 8.5)
        }
        return mids
    }

    // MARK: - 支撑压力线

    private func drawSRLevels(ctx: GraphicsContext, size: CGSize) {
        guard !srLevels.isEmpty else { return }
        let plotBottom = size.height - layout.bottomMargin
        let tagW = layout.rightMargin - 6
        // 价签画在右侧价格轴上（与最新价 pill 同列）；按 y 错开，避免互相叠字
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
            var labelY = y - 8.5
            if labelY < lastLabelBottom + 2 { labelY = lastLabelBottom + 2 }
            labelY = min(max(labelY, layout.topMargin), plotBottom - 17)
            lastLabelBottom = labelY + 17
            let rect = CGRect(x: size.width - layout.rightMargin + 3, y: labelY, width: tagW, height: 17)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color.opacity(0.92)))
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: 3.8),
                       with: .color(.white.opacity(0.18)), lineWidth: 0.6)
            ctx.draw(
                Text(String(format: "%.2f", level.price))
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .tracking(0.2)
                    .foregroundColor(.white),
                at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center
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

    private func drawAxes(ctx: GraphicsContext, size: CGSize, skipYs: [ClosedRange<CGFloat>] = []) {
        let step = ChartLayout.niceStep(range: layout.priceMax - layout.priceMin)
        var p = ceil(layout.priceMin / step) * step
        let axisX = size.width - layout.rightMargin / 2
        while p <= layout.priceMax {
            let y = layout.y(price: p)
            let blocked = skipYs.contains { $0.contains(y) }
            if !blocked {
                ctx.draw(
                    Text(String(format: "%.2f", p))
                        .font(.system(size: 9.5, weight: .regular).monospacedDigit())
                        .tracking(0.2)
                        .foregroundColor(Color.dsTextTertiary),
                    at: CGPoint(x: axisX, y: y), anchor: .center
                )
            }
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
