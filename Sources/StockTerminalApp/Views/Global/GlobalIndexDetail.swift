import SwiftUI
import DesignSystem
import TradingCore

/// 全球指数详情：布局与交互沿用个股 ChartPanel（头部 / 周期 Tab / 分时·蜡烛 / 副图指标）。
struct GlobalIndexDetail: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewport = Viewport()
    @State private var overlayKind: MainOverlay = .ma
    @State private var subKind: SubIndicator = .macd
    @State private var showSR = true

    var body: some View {
        let store = env.globalMarkets
        if let index = store.selected {
            let quote = store.quotes[index.id]
            VStack(spacing: 0) {
                header(index, quote: quote, now: store.now)
                toolbar
                chartArea(index)
            }
            .onChange(of: store.selectedID) { _, _ in viewport.reset() }
            .onChange(of: store.chartTab) { _, _ in viewport.reset() }
        } else {
            EmptyHint(text: "点击卡片查看指数详情")
        }
    }

    // MARK: - 头部（与个股 ChartHeader 同款）

    private func header(_ index: GlobalIndex, quote: GlobalIndexQuote?, now: Date) -> some View {
        let trading = index.isTrading(at: now)
        let last = quote.map { Decimal($0.last) }
        let change = quote.map { Decimal($0.change) }
        let open = quote?.open.map { Decimal($0) }
        let high = quote?.high.map { Decimal($0) }
        let low = quote?.low.map { Decimal($0) }
        let pre = quote?.preClose.map { Decimal($0) }
        let amplitude: Double? = {
            guard let q = quote, let h = q.high, let l = q.low, let p = q.preClose, p > 0 else { return nil }
            return (h - l) / p * 100
        }()

        var tags: [(String, Color)] = [
            (index.market, .dsTextSecondary),
            (index.region.rawValue, .dsTextTertiary),
            ("指数", .dsInfo),
        ]
        if trading { tags.append(("实时", .dsAccent)) }

        return ChartHeader(
            name: index.name,
            tags: tags,
            lastPrice: last,
            change: change,
            changePercent: quote?.changePercent,
            open: open,
            high: high,
            low: low,
            preClose: pre,
            amplitude: amplitude,
            leading: AnyView(backButton)
        )
    }

    private var backButton: some View {
        Button {
            env.globalMarkets.clearSelection()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsTextSecondary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.dsElevated.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.dsBorder, lineWidth: 0.6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("返回全球市场")
    }

    // MARK: - 工具条（与个股一致）

    private var toolbar: some View {
        let store = env.globalMarkets
        return HStack(spacing: 12) {
            HStack(spacing: 1) {
                ForEach(Array(GlobalMarketStore.ChartTab.allCases.enumerated()), id: \.element) { idx, tab in
                    TimeFrameTab(label: tab.rawValue, index: idx, selected: store.chartTab == tab) {
                        store.setChartTab(tab)
                    }
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.dsInput))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.dsBorder, lineWidth: 0.6))

            Spacer()

            if store.chartTab != .timeShare {
                HStack(spacing: 2) {
                    ForEach(MainOverlay.allCases, id: \.self) { kind in
                        MiniTab(label: kind.label, active: overlayKind == kind) {
                            overlayKind = kind
                        }
                    }
                    Rectangle().fill(Color.dsBorder).frame(width: 0.5, height: 11)
                        .padding(.horizontal, 3)
                    MiniTab(label: "支撑压力", active: showSR) { showSR.toggle() }
                        .help("支撑压力：自动识别摆动高低点并聚类")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder.opacity(0.55)).frame(height: 0.5)
        }
    }

    // MARK: - 主图

    @ViewBuilder
    private func chartArea(_ index: GlobalIndex) -> some View {
        let store = env.globalMarkets
        let series = store.activeSeries
        let loading = store.historyLoading.contains { $0.hasSuffix(":\(index.id)") }

        Group {
            if store.chartTab == .timeShare, index.tencentMinuteCode == nil {
                EmptyHint(text: "该市场暂无分时数据，可切换日K / 周K / 月K")
            } else if let s = series, !s.isEmpty, s.timeFrame == .timeShare {
                TimeShareChartView(series: s, viewport: viewport)
            } else if let s = series, !s.isEmpty {
                VStack(spacing: 0) {
                    CandleChartView(series: s, viewport: viewport, overlayKind: overlayKind, showSR: showSR)
                    Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)
                    subPaneBar
                    if subKind == .vol {
                        globalVolumeStrip(series: s)
                            .frame(height: 56)
                    } else {
                        IndicatorPane(series: s, viewport: viewport, kind: subKind)
                            .frame(height: 62)
                    }
                }
            } else if loading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyHint(text: store.chartTab == .timeShare
                          ? "分时加载中或暂不可用"
                          : "K 线加载中或暂不可用")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

    private func globalVolumeStrip(series: KLineSeries) -> some View {
        let hover = viewport.hoverPoint
        return GeometryReader { geo in
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
