import SwiftUI
import TradingCore

/// 副图指标面板：MACD / KDJ / RSI 通用渲染（主图同一 viewport，列对齐）
/// 十字星悬停时图例跟随悬停那一根；无悬停时显示可见区最后一根（切换周期后 viewport 会清空悬停）。
struct IndicatorPane: View {
    let series: KLineSeries
    let viewport: Viewport
    let kind: SubIndicator

    /// 线与线、线与其对应的配色（DIF/K/RSI6 白，DEA/D/RSI12 金，J/RSI24 紫）
    private static let palette: [Color] = [.dsTextPrimary, .dsMA5, .dsMA20]

    var body: some View {
        let bars = series.bars
        let data = series.subIndicatorData(kind)
        let hover = viewport.hoverPoint
        GeometryReader { geo in
            let layout = ChartLayout(
                size: geo.size, bars: bars,
                visibleCount: viewport.visibleCount, offsetFromEnd: viewport.offsetFromEnd,
                bottomMargin: 2, topMargin: 2
            )
            Canvas { ctx, size in
                draw(ctx: ctx, size: size, layout: layout, bars: bars, data: data, hover: hover)
            }
        }
    }

    private func draw(
        ctx: GraphicsContext, size: CGSize, layout: ChartLayout,
        bars: [KLine], data: SubIndicatorData, hover: CGPoint?
    ) {
        guard !bars.isEmpty, layout.visible.count > 0 else { return }
        let lo = layout.visible.lowerBound
        let upper = min(layout.visible.upperBound, bars.count)
        guard upper > lo else { return }
        let focusIdx = Self.focusIndex(hover: hover, layout: layout, lower: lo, upper: upper)

        // 可见区间数值范围
        var minV = Double.greatestFiniteMagnitude
        var maxV = -Double.greatestFiniteMagnitude
        func scan(_ v: Double?) {
            guard let v else { return }
            minV = min(minV, v)
            maxV = max(maxV, v)
        }
        for line in data.lines {
            for i in lo..<upper where i < line.values.count { scan(line.values[i]) }
        }
        if let hist = data.histogram {
            for i in lo..<upper where i < hist.count { scan(hist[i]) }
        }
        if data.zeroCentered {
            minV = min(minV, 0)
            maxV = max(maxV, 0)
        }
        guard minV <= maxV else { return }
        let pad = max(maxV - minV, 1e-9) * 0.12
        minV -= pad
        maxV += pad
        let span = max(maxV - minV, 1e-9)
        func y(_ v: Double) -> CGFloat {
            let t = (v - minV) / span
            return 2 + (size.height - 4) * (1 - CGFloat(t))
        }

        // 零轴
        if data.zeroCentered {
            let y0 = y(0)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y0))
            line.addLine(to: CGPoint(x: size.width - layout.rightMargin, y: y0))
            ctx.stroke(line, with: .color(Color.dsBorder.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
        }

        // 柱状（MACD）
        if let hist = data.histogram {
            let w = max(layout.candleSpacing * 0.7, 1)
            var upPath = Path(), downPath = Path()
            for i in lo..<upper where i < hist.count {
                guard let v = hist[i] else { continue }
                let x = layout.x(index: i)
                let y0 = y(0), y1 = y(v)
                let rect = CGRect(x: x - w / 2, y: min(y0, y1), width: w, height: max(abs(y1 - y0), 1))
                if v >= 0 { upPath.addRect(rect) } else { downPath.addRect(rect) }
            }
            ctx.fill(upPath, with: .color(Sem.up.opacity(0.62)))
            ctx.fill(downPath, with: .color(Sem.down.opacity(0.62)))
        }

        // 指标线
        for (idx, line) in data.lines.enumerated() {
            let color = Self.palette[min(idx, Self.palette.count - 1)]
            var path = Path()
            var started = false
            for i in lo..<upper where i < line.values.count {
                guard let v = line.values[i] else { started = false; continue }
                let pt = CGPoint(x: layout.x(index: i), y: y(v))
                if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1)
        }

        // 十字星竖线（与主图列对齐）
        if hover != nil {
            let x = layout.x(index: focusIdx)
            var vline = Path()
            vline.move(to: CGPoint(x: x, y: 0))
            vline.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(vline, with: .color(Color.dsTextSecondary.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
        }

        // 图例：跟随十字星那一根（无悬停 → 可见区最后一根）
        var attr = AttributedString(kind.displayName + "  ")
        attr.foregroundColor = Color.dsTextTertiary
        attr.font = .system(size: 10, weight: .medium).monospacedDigit()
        for (lineIdx, line) in data.lines.enumerated() {
            let color = Self.palette[min(lineIdx, Self.palette.count - 1)]
            var name = AttributedString(line.name + ": ")
            name.foregroundColor = color
            name.font = .system(size: 10, weight: .medium).monospacedDigit()
            attr += name
            let v = (focusIdx < line.values.count) ? line.values[focusIdx] : nil
            var val = AttributedString((v.map { String(format: "%.2f  ", $0) } ?? "--  "))
            val.foregroundColor = Color.dsTextSecondary
            val.font = .system(size: 10, weight: .medium).monospacedDigit()
            attr += val
        }
        if let hist = data.histogram {
            let v = (focusIdx < hist.count) ? hist[focusIdx] : nil
            var name = AttributedString("MACD: ")
            name.foregroundColor = Color.dsTextTertiary
            name.font = .system(size: 10, weight: .medium).monospacedDigit()
            attr += name
            var val = AttributedString((v.map { String(format: "%.2f", $0) } ?? "--"))
            val.foregroundColor = v.map { $0 >= 0 } == true ? Sem.up : Sem.down
            val.font = .system(size: 10, weight: .medium).monospacedDigit()
            attr += val
        }
        ctx.draw(Text(attr), at: CGPoint(x: 6, y: 2), anchor: .topLeading)
    }

    /// 与 CrosshairCanvas 同一套取位：悬停 x → bar 下标，夹在可见区内。
    static func focusIndex(hover: CGPoint?, layout: ChartLayout, lower: Int, upper: Int) -> Int {
        guard upper > lower else { return 0 }
        guard let hover else { return upper - 1 }
        return min(max(layout.index(x: hover.x), lower), upper - 1)
    }
}
