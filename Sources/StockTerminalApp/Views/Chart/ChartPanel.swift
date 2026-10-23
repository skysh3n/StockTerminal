import SwiftUI
import DesignSystem
import TradingCore

/// 蜡烛图容器：手势（悬停十字光标 / 拖拽平移 / 滚轮+捏合缩放 / 双击复位）
/// 交互状态全部写入 Viewport；主图 body 不读 hoverPoint —— 光标移动只重绘 CrosshairCanvas 层。
struct CandleChartView: View {
    let series: KLineSeries
    let viewport: Viewport
    let overlayKind: MainOverlay
    let showSR: Bool
    /// 是否允许捏合 / 双指纵向滚轮缩放。全球指数关闭，只保留左右平移。
    var allowsZoom: Bool = true
    /// 平移灵敏度：>1 同样拖动距离移动更多根 K 线。
    var panSensitivity: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let bars = series.bars
            let lines = Self.chartLines(series.overlayLines(overlayKind), kind: overlayKind)
            let srLevels = showSR ? SupportResistance.levels(bars: bars) : []
            let layout = ChartLayout(
                size: geo.size, bars: bars,
                visibleCount: viewport.visibleCount, offsetFromEnd: viewport.offsetFromEnd
            )
            ZStack {
                Color.clear
                if bars.isEmpty {
                    EmptyHint(text: "行情加载中…")
                } else {
                    CandlestickCanvas(
                        bars: bars, lines: lines, srLevels: srLevels, layout: layout,
                        preClose: series.preClose?.doubleValue, tf: series.timeFrame
                    )
                    CrosshairCanvas(
                        bars: bars, layout: layout, tf: series.timeFrame,
                        viewport: viewport, preClose: series.preClose?.doubleValue
                    )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): viewport.hoverPoint = p
                case .ended: viewport.hoverPoint = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { g in
                        // 只取横向位移，避免触控板纵向滑动干扰平移。
                        viewport.pan(
                            translationX: g.translation.width * panSensitivity,
                            spacing: layout.candleSpacing,
                            totalBars: bars.count
                        )
                    }
                    .onEnded { _ in viewport.panStartOffset = nil }
            )
            .modifier(CandleZoomGestures(enabled: allowsZoom, viewport: viewport))
            .onTapGesture(count: 2) { viewport.reset() }
        }
    }

    /// 指标线 → 配色（MA/EMA 四色，BOLL 白/金/紫）
    static func chartLines(_ lines: [IndicatorLine], kind: MainOverlay) -> [ChartLine] {
        let palette: [Color] = kind == .boll
            ? [.dsTextPrimary, .dsMA5, .dsMA20]
            : [.dsMA5, .dsMA10, .dsMA20, .dsMA60]
        return lines.enumerated().map { idx, line in
            ChartLine(name: line.name, color: palette[min(idx, palette.count - 1)], values: line.values)
        }
    }
}

/// 捏合 + 滚轮缩放；全球指数可关掉，只保留左右拖拽平移。
private struct CandleZoomGestures: ViewModifier {
    let enabled: Bool
    let viewport: Viewport

    func body(content: Content) -> some View {
        if enabled {
            content
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { g in viewport.pinch(magnification: g.magnification) }
                        .onEnded { _ in viewport.pinchStartCount = nil }
                )
                .overlay(WheelCatcher { dy in viewport.wheelZoom(deltaY: dy) })
        } else {
            content
        }
    }
}

/// 图表头部：双行结构——标题行（名称/标签 · 右侧大字现价与涨跌）+ 指标条（自适应宽度不裁切）
/// 个股与全球指数共用同一套视觉。
struct ChartHeader: View {
    let name: String
    let tags: [(text: String, color: Color)]
    let lastPrice: Decimal?
    let change: Decimal?
    let changePercent: Double?
    let open: Decimal?
    let high: Decimal?
    let low: Decimal?
    let preClose: Decimal?
    let amplitude: Double?
    let volume: Int64?
    let turnover: Decimal?
    /// 标题行左侧额外内容（例如全球详情的返回按钮）
    var leading: AnyView? = nil

    init(state: SymbolState?) {
        let q = state?.quote
        self.name = state?.symbol.name ?? "--"
        if let sym = state?.symbol {
            self.tags = [
                (sym.fullCode, .dsTextSecondary),
                (sym.exchange.rawValue, .dsTextTertiary),
            ]
        } else {
            self.tags = []
        }
        self.lastPrice = q?.lastPrice
        self.change = q?.change
        self.changePercent = q?.changePercent
        self.open = q?.open
        self.high = q?.high
        self.low = q?.low
        self.preClose = q?.preClose
        self.amplitude = q?.amplitude
        self.volume = q?.volume
        self.turnover = q?.turnover
        self.leading = nil
    }

    init(
        name: String,
        tags: [(String, Color)],
        lastPrice: Decimal?,
        change: Decimal?,
        changePercent: Double?,
        open: Decimal?,
        high: Decimal?,
        low: Decimal?,
        preClose: Decimal?,
        amplitude: Double?,
        volume: Int64? = nil,
        turnover: Decimal? = nil,
        leading: AnyView? = nil
    ) {
        self.name = name
        self.tags = tags.map { (text: $0.0, color: $0.1) }
        self.lastPrice = lastPrice
        self.change = change
        self.changePercent = changePercent
        self.open = open
        self.high = high
        self.low = low
        self.preClose = preClose
        self.amplitude = amplitude
        self.volume = volume
        self.turnover = turnover
        self.leading = leading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 7) {
                    if let leading { leading }
                    Text(name)
                        .font(.dsHeadline())
                        .tracking(-0.2)
                        .foregroundStyle(Color.dsTextPrimary)
                    ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                        Tag(text: tag.text, color: tag.color)
                    }
                }

                Spacer(minLength: 10)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Fmt.price(lastPrice))
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .tracking(-0.5)
                        .foregroundStyle(Sem.change(changePercent))
                    ChangeChip(text: Fmt.pct(changePercent), color: Sem.change(changePercent))
                    Text(Fmt.signed(change))
                        .font(.dsFootnote(medium: true))
                        .foregroundStyle(Sem.change(changePercent).opacity(0.9))
                }
            }

            HStack(alignment: .center, spacing: 18) {
                statItem("今开", Fmt.price(open), Sem.price(open, ref: preClose))
                statItem("最高", Fmt.price(high), Sem.price(high, ref: preClose))
                statItem("最低", Fmt.price(low), Sem.price(low, ref: preClose))
                statItem("昨收", Fmt.price(preClose), .dsTextSecondary)
                statItem("振幅", amplitude.map { String(format: "%.2f%%", $0) } ?? "--", .dsTextSecondary)
                if volume != nil || turnover != nil {
                    statItem("成交量", volume.map { Fmt.volume(shares: $0) } ?? "--", .dsTextSecondary)
                    statItem("成交额", Fmt.amount(turnover), .dsTextSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder.opacity(0.7)).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func statItem(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dsMicro())
                .tracking(0.3)
                .foregroundStyle(Color.dsTextTertiary)
            Text(value)
                .font(.dsFootnote())
                .foregroundStyle(color)
        }
    }
}

/// 周期 Tab（⌘1..⌘5）：分段控件中的内嵌浮起单元。个股与全球指数共用。
struct TimeFrameTab: View {
    let label: String
    let index: Int
    let selected: Bool
    let action: () -> Void
    var shortcut: Bool = true
    @State private var hovering = false

    init(tf: TimeFrame, index: Int, selected: Bool, action: @escaping () -> Void) {
        self.label = tf.label
        self.index = index
        self.selected = selected
        self.action = action
        self.shortcut = true
    }

    init(label: String, index: Int, selected: Bool, shortcut: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.index = index
        self.selected = selected
        self.action = action
        self.shortcut = shortcut
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.dsFootnote(medium: selected))
                .tracking(0.2)
                .foregroundStyle(selected ? Color.dsAccent
                                 : hovering ? Color.dsTextPrimary : Color.dsTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 5.5)
                        .fill(selected ? Color.dsElevated
                              : hovering ? Color.dsHover.opacity(0.55) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5.5)
                        .stroke(selected ? Color.dsBorderStrong.opacity(0.8) : .clear, lineWidth: 0.6)
                )
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .modifier(OptionalCommandShortcut(enabled: shortcut, index: index, label: label))
    }
}

private struct OptionalCommandShortcut: ViewModifier {
    let enabled: Bool
    let index: Int
    let label: String

    func body(content: Content) -> some View {
        if enabled {
            content
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .help("\(label)（⌘\(index + 1)）")
        } else {
            content.help(label)
        }
    }
}

/// 微型 Tab（主图叠加指标 / 副图指标 / 支撑压力开关）
struct MiniTab: View {
    let label: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.dsMicro(medium: active))
                .tracking(0.4)
                .foregroundStyle(active ? Color.dsAccent
                                 : hovering ? Color.dsTextSecondary : Color.dsTextTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.dsAccent.opacity(0.12)
                              : hovering ? Color.dsHover.opacity(0.55) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(active ? Color.dsAccent.opacity(0.35) : .clear, lineWidth: 0.6)
                )
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
    }
}

/// 中栏图表面板：头部 + 周期/叠加指标选择 + 主图 + 副图（VOL/MACD/KDJ/RSI）
struct ChartPanel: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewport = Viewport()
    @State private var overlayKind: MainOverlay = .ma
    @State private var subKind: SubIndicator = .macd
    @State private var showSR = true

    var body: some View {
        @Bindable var wl = env.watchlist
        let code = wl.selectedCode
        let state = code.flatMap { env.market.states[$0] }
        let series = env.market.activeSeries

        VStack(spacing: 0) {
            ChartHeader(state: state)

            HStack(spacing: 12) {
                HStack(spacing: 1) {
                    ForEach(Array(TimeFrame.chartCases.enumerated()), id: \.element) { idx, tf in
                        TimeFrameTab(tf: tf, index: idx, selected: wl.selectedTimeFrame == tf) {
                            wl.selectedTimeFrame = tf
                        }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.dsInput))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.dsBorder, lineWidth: 0.6))

                Spacer()

                HStack(spacing: 2) {
                    ForEach(MainOverlay.allCases, id: \.self) { kind in
                        MiniTab(label: kind.label, active: overlayKind == kind) {
                            overlayKind = kind
                        }
                    }
                    Rectangle().fill(Color.dsBorder).frame(width: 0.5, height: 11)
                        .padding(.horizontal, 3)
                    MiniTab(label: "支撑压力", active: showSR) { showSR.toggle() }
                        .help("支撑压力：自动识别摆动高低点并聚类（触及越多越粗）")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.dsBorder.opacity(0.55)).frame(height: 0.5)
            }

            Group {
                if let s = series, s.timeFrame == .timeShare {
                    TimeShareChartView(series: s, viewport: viewport)
                } else if let s = series {
                    VStack(spacing: 0) {
                        CandleChartView(series: s, viewport: viewport, overlayKind: overlayKind, showSR: showSR)
                        Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)
                        subPaneBar
                        if subKind == .vol {
                            VolumeStrip(series: s, viewport: viewport)
                                .frame(height: 56)
                        } else {
                            IndicatorPane(series: s, viewport: viewport, kind: subKind)
                                .frame(height: 62)
                        }
                    }
                } else {
                    EmptyHint(text: "选择左侧股票开始看盘")
                }
            }
        }
        .onChange(of: code) { _, _ in viewport.reset() }
        .onChange(of: wl.selectedTimeFrame) { _, _ in viewport.reset() }
    }

    /// 副图指标 Tab（VOL/MACD/KDJ/RSI）
    private var subPaneBar: some View {
        HStack(spacing: 2) {
            ForEach(SubIndicator.allCases, id: \.self) { kind in
                MiniTab(label: kind.label, active: subKind == kind) {
                    subKind = kind
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder.opacity(0.4)).frame(height: 0.5)
        }
    }
}

/// 成交量副图容器（读取 bars 构建对齐 layout；观察 hover 以刷新十字星读数）
private struct VolumeStrip: View {
    let series: KLineSeries
    let viewport: Viewport

    var body: some View {
        let hover = viewport.hoverPoint
        GeometryReader { geo in
            let bars = series.bars
            let layout = ChartLayout(
                size: geo.size, bars: bars,
                visibleCount: viewport.visibleCount, offsetFromEnd: viewport.offsetFromEnd,
                bottomMargin: 2, topMargin: 2
            )
            VolumePane(bars: bars, layout: layout, hover: hover)
        }
    }
}
