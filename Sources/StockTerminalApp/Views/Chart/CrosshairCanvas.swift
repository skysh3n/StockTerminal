import SwiftUI
import TradingCore

/// 十字光标独立覆盖层：只观察 viewport.hoverPoint——
/// 鼠标移动 60Hz 只重绘这一层细线与标签，主图（几百根蜡烛）纹丝不动。
struct CrosshairCanvas: View {
    let bars: [KLine]
    let layout: ChartLayout
    let tf: TimeFrame
    let viewport: Viewport
    let preClose: Double?

    var body: some View {
        let hover = viewport.hoverPoint
        Canvas { ctx, size in
            guard let hover, !bars.isEmpty, layout.visible.count > 0 else { return }
            let upper = min(layout.visible.upperBound, bars.count)
            guard upper > layout.visible.lowerBound else { return }
            let idx = min(max(layout.index(x: hover.x), layout.visible.lowerBound), upper - 1)
            let bar = bars[idx]
            let x = layout.x(index: idx)
            let plotBottom = size.height - layout.bottomMargin

            // 竖线
            var v = Path()
            v.move(to: CGPoint(x: x, y: layout.topMargin))
            v.addLine(to: CGPoint(x: x, y: plotBottom))
            ctx.stroke(v, with: .color(Color.dsTextSecondary.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))

            // 横线（限制在绘图区内）
            let hy = min(max(hover.y, layout.topMargin), plotBottom)
            var h = Path()
            h.move(to: CGPoint(x: 0, y: hy))
            h.addLine(to: CGPoint(x: size.width - layout.rightMargin, y: hy))
            ctx.stroke(h, with: .color(Color.dsTextSecondary.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))

            // 右轴价格标签（保持原涨跌配色 + 白字）
            let price = layout.price(y: hy)
            let priceColor: Color = {
                guard let pre = preClose else { return .dsElevated }
                return price > pre ? Sem.up : price < pre ? Sem.down : .dsFlat
            }()
            drawTag(ctx: ctx,
                    text: String(format: "%.2f", price),
                    rect: CGRect(x: size.width - layout.rightMargin + 3, y: hy - 8.5,
                                 width: layout.rightMargin - 6, height: 17),
                    bg: priceColor, lightText: true)

            // 底部日期：浅色主题下用主文字色，避免白字配浅底看不清
            let timeText = Fmt.chartTime(bar.timestamp, tf: tf)
            let tw = CGFloat(timeText.count) * 6.6 + 12
            drawTag(ctx: ctx, text: timeText,
                    rect: CGRect(x: x - tw / 2, y: plotBottom + 1, width: tw, height: 15),
                    bg: Color.dsElevated, lightText: false)

            // 左上信息框：时间 / OHLC / 涨跌 / 成交量
            drawInfoBox(ctx: ctx, bar: bar, idx: idx)
        }
        .allowsHitTesting(false)
    }

    private func drawTag(ctx: GraphicsContext, text: String, rect: CGRect, bg: Color, lightText: Bool) {
        ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(bg))
        ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: 3.8),
                   with: .color(lightText ? .white.opacity(0.16) : Color.dsBorderStrong.opacity(0.55)),
                   lineWidth: 0.6)
        ctx.draw(
            Text(text)
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .tracking(0.2)
                .foregroundColor(lightText ? .white : .dsTextPrimary),
            at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center
        )
    }

    private func drawInfoBox(ctx: GraphicsContext, bar: KLine, idx: Int) {
        let pre = preClose ?? bar.open.doubleValue
        let close = bar.close.doubleValue
        let pct = pre > 0 ? (close - pre) / pre * 100 : 0
        func colorFor(_ v: Double) -> Color {
            v > pre ? Sem.up : v < pre ? Sem.down : Sem.flat
        }
        let color = colorFor(close)

        let line1: [(String, Color)] = [
            (Fmt.chartTime(bar.timestamp, tf: tf) + "  ", .dsTextSecondary),
        ]
        let line2: [(String, Color)] = [
            ("开 ", .dsTextTertiary), (String(format: "%.2f  ", bar.open.doubleValue), colorFor(bar.open.doubleValue)),
            ("高 ", .dsTextTertiary), (String(format: "%.2f  ", bar.high.doubleValue), colorFor(bar.high.doubleValue)),
            ("低 ", .dsTextTertiary), (String(format: "%.2f  ", bar.low.doubleValue), colorFor(bar.low.doubleValue)),
            ("收 ", .dsTextTertiary), (String(format: "%.2f", close), color),
        ]
        let line3: [(String, Color)] = [
            ("涨跌 ", .dsTextTertiary), (String(format: "%+.2f%%", pct), color),
            ("   量 ", .dsTextTertiary), (Fmt.volume(shares: bar.volume), .dsTextSecondary),
        ]

        var attr = AttributedString()
        for lines in [line1, line2, line3] {
            for (text, c) in lines {
                var s = AttributedString(text)
                s.foregroundColor = c
                s.font = .system(size: 10, weight: .medium).monospacedDigit()
                attr += s
            }
            attr += AttributedString("\n")
        }

        // 半透明浮层底（发丝描边）
        let boxRect = CGRect(x: 6, y: 4, width: 322, height: 48)
        ctx.fill(Path(roundedRect: boxRect, cornerRadius: 6),
                 with: .color(Color.dsElevated.opacity(0.88)))
        ctx.stroke(Path(roundedRect: boxRect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: 5.8),
                   with: .color(Color.dsBorderStrong.opacity(0.6)), lineWidth: 0.6)
        ctx.draw(Text(attr), at: CGPoint(x: 14, y: 9), anchor: .topLeading)
    }
}
