import SwiftUI
import Charts
import DesignSystem
import TradingCore

/// 指数详情：概览 + 分时 / 日K / 周K / 月K。指数不可交易，无下单入口。
struct GlobalIndexDetail: View {
    @Environment(AppEnvironment.self) private var env
    @State private var hoverDate: Date?

    var body: some View {
        let store = env.globalMarkets
        if let index = store.selected {
            let quote = store.quotes[index.id]
            let dayAll = store.dayHistory[index.id] ?? []
            VStack(alignment: .leading, spacing: 0) {
                backBar
                Rectangle().fill(Color.dsBorder.opacity(0.6)).frame(height: 0.5)
                header(index, quote: quote, now: store.now)
                Rectangle().fill(Color.dsBorder.opacity(0.6)).frame(height: 0.5)
                stats(quote: quote, dayAll: dayAll)
                Rectangle().fill(Color.dsBorder.opacity(0.6)).frame(height: 0.5)
                chartSection(index)
                Rectangle().fill(Color.dsBorder.opacity(0.6)).frame(height: 0.5)
                readOnlyNote
            }
            .onChange(of: store.selectedID) { _, _ in hoverDate = nil }
            .onChange(of: store.chartTab) { _, _ in hoverDate = nil }
        } else {
            EmptyHint(text: "点击卡片查看指数详情")
        }
    }

    private var backBar: some View {
        Button {
            env.globalMarkets.clearSelection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("全球市场")
                    .font(.dsFootnote(medium: true))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.dsAccent)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("返回全球市场总览")
    }

    // MARK: - 头部

    private func header(_ index: GlobalIndex, quote: GlobalIndexQuote?, now: Date) -> some View {
        let color = Sem.change(quote?.changePercent)
        let trading = index.isTrading(at: now)
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(index.name)
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.dsTextPrimary)
                    Tag(text: index.region.rawValue, color: .dsTextTertiary)
                    Tag(text: "指数 · 只读", color: .dsInfo)
                    if trading {
                        Tag(text: "实时", color: .dsAccent)
                    }
                }
                HStack(spacing: 10) {
                    MarketStatusLabel(market: index.market, trading: trading)
                    Text("当地时间 \(Self.localTime(now, timeZone: index.session.timeZone))")
                        .font(.dsMicro())
                        .foregroundStyle(Color.dsTextTertiary)
                    Text("常规时段 \(Self.sessionText(index.session))")
                        .font(.dsMicro())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(GlobalFmt.value(quote?.last))
                    .font(.system(size: 28, weight: .semibold).monospacedDigit())
                    .tracking(-0.5)
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                HStack(spacing: 8) {
                    Text(GlobalFmt.signed(quote?.change))
                        .font(.dsFootnote(medium: true))
                        .foregroundStyle(color)
                    ChangeChip(text: Fmt.pct(quote?.changePercent), color: color)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .animation(.easeOut(duration: 0.2), value: quote?.last)
    }

    // MARK: - 统计

    private func stats(quote: GlobalIndexQuote?, dayAll: [GlobalIndexBar]) -> some View {
        let year = dayAll.suffix(250)
        let amplitude: Double? = {
            guard let q = quote, let h = q.high, let l = q.low, let pre = q.preClose, pre > 0 else { return nil }
            return (h - l) / pre * 100
        }()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 4)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            stat("昨收", GlobalFmt.value(quote?.preClose))
            stat("今开", GlobalFmt.value(quote?.open), color: priceColor(quote?.open, ref: quote?.preClose))
            stat("最高", GlobalFmt.value(quote?.high), color: priceColor(quote?.high, ref: quote?.preClose))
            stat("最低", GlobalFmt.value(quote?.low), color: priceColor(quote?.low, ref: quote?.preClose))
            stat("振幅", amplitude.map { String(format: "%.2f%%", $0) } ?? "--")
            stat("涨跌额", GlobalFmt.signed(quote?.change), color: Sem.change(quote?.changePercent))
            stat("52周最高", GlobalFmt.value(year.map(\.high).max()))
            stat("52周最低", GlobalFmt.value(year.map(\.low).min()))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func stat(_ label: String, _ value: String, color: Color = .dsTextPrimary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.dsMicro())
                .tracking(0.3)
                .foregroundStyle(Color.dsTextTertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private func priceColor(_ v: Double?, ref: Double?) -> Color {
        guard let v, let ref else { return .dsTextPrimary }
        return Sem.change(v - ref)
    }

    // MARK: - 图表区

    private func chartSection(_ index: GlobalIndex) -> some View {
        let store = env.globalMarkets
        let bars = store.chartBars(for: index.id)
        let loadingKey: String = {
            switch store.chartTab {
            case .timeShare: return "min:\(index.id)"
            case .day: return "day:\(index.id)"
            case .week: return "week:\(index.id)"
            case .month: return "month:\(index.id)"
            }
        }()
        let loading = store.historyLoading.contains(loadingKey)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(GlobalMarketStore.ChartTab.allCases) { tab in
                    tabButton(tab)
                }
                Spacer(minLength: 8)
                if store.chartTab == .day, index.history != nil {
                    ForEach(GlobalMarketStore.DayRange.allCases) { r in
                        dayRangeButton(r)
                    }
                }
            }

            Group {
                switch store.chartTab {
                case .timeShare:
                    timeShareBody(index, bars: bars, loading: loading)
                case .day, .week, .month:
                    candleBody(index, bars: bars, loading: loading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity)
    }

    private func tabButton(_ tab: GlobalMarketStore.ChartTab) -> some View {
        let store = env.globalMarkets
        let selected = store.chartTab == tab
        return Button {
            store.setChartTab(tab)
        } label: {
            Text(tab.rawValue)
                .font(.dsFootnote(medium: selected))
                .foregroundStyle(selected ? Color.dsAccent : Color.dsTextTertiary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? Color.dsAccent.opacity(0.12) : Color.clear)
                )
                .overlay(alignment: .bottom) {
                    if selected {
                        Rectangle().fill(Color.dsAccent).frame(height: 1.5).padding(.horizontal, 8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayRangeButton(_ r: GlobalMarketStore.DayRange) -> some View {
        let store = env.globalMarkets
        let selected = store.dayRange == r
        return Button {
            store.dayRange = r
        } label: {
            Text(r.rawValue)
                .font(.dsMicro(medium: selected))
                .foregroundStyle(selected ? Color.dsAccent : Color.dsTextTertiary)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Color.dsAccent.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func timeShareBody(_ index: GlobalIndex, bars: [GlobalIndexBar], loading: Bool) -> some View {
        if index.tencentMinuteCode == nil {
            EmptyHint(text: "该市场暂无分时数据，可切换日K / 周K / 月K 查看走势")
        } else if bars.count >= 2 {
            timeShareChart(bars, preClose: env.globalMarkets.minutePreClose(for: index.id)
                           ?? env.globalMarkets.quotes[index.id]?.preClose)
        } else if loading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyHint(text: "分时暂时获取失败，稍后重试或切换到日K")
        }
    }

    @ViewBuilder
    private func candleBody(_ index: GlobalIndex, bars: [GlobalIndexBar], loading: Bool) -> some View {
        if index.history == nil {
            EmptyHint(text: "该指数暂无历史 K 线，仅提供实时快照")
        } else if bars.count >= 2 {
            candleChart(bars)
        } else if loading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyHint(text: "K 线暂时获取失败，稍后重新选择即可重试")
        }
    }

    // MARK: - 分时图

    private func timeShareChart(_ bars: [GlobalIndexBar], preClose: Double?) -> some View {
        let last = bars[bars.count - 1].close
        let ref = preClose ?? bars[0].close
        let color = Sem.change(last - ref)
        let prices = bars.map(\.close) + [ref]
        let lo = prices.min() ?? ref
        let hi = prices.max() ?? ref
        let pad = max((hi - lo) * 0.08, ref * 0.001)
        let domain = (lo - pad)...(hi + pad)
        let focus = hoverDate.flatMap { Self.nearest(bars, to: $0) }

        return VStack(alignment: .leading, spacing: 6) {
            timeShareReadout(focus ?? bars[bars.count - 1], preClose: ref, hovering: focus != nil)

            Chart {
                ForEach(bars) { b in
                    AreaMark(
                        x: .value("时间", b.date),
                        yStart: .value("基线", domain.lowerBound),
                        yEnd: .value("价", b.close)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    LineMark(x: .value("时间", b.date), y: .value("价", b.close))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
                }
                if let preClose {
                    RuleMark(y: .value("昨收", preClose))
                        .foregroundStyle(Color.dsTextTertiary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 0.7, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("昨收 \(GlobalFmt.value(preClose))")
                                .font(.dsMicro())
                                .foregroundStyle(Color.dsTextTertiary)
                        }
                }
                if let focus {
                    RuleMark(x: .value("时间", focus.date))
                        .foregroundStyle(Color.dsTextTertiary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    PointMark(x: .value("时间", focus.date), y: .value("价", focus.close))
                        .symbolSize(36)
                        .foregroundStyle(color)
                }
            }
            .chartYScale(domain: domain)
            .chartXSelection(value: $hoverDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.dsBorder.opacity(0.3))
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .foregroundStyle(Color.dsTextTertiary)
                        .font(.dsMicro())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.dsBorder.opacity(0.3))
                    AxisValueLabel()
                        .foregroundStyle(Color.dsTextTertiary)
                        .font(.dsMicro())
                }
            }
        }
    }

    private func timeShareReadout(_ bar: GlobalIndexBar, preClose: Double, hovering: Bool) -> some View {
        let pct = preClose > 0 ? (bar.close / preClose - 1) * 100 : nil
        return HStack(spacing: 12) {
            Text(Self.minuteText(bar.date))
                .foregroundStyle(hovering ? Color.dsTextPrimary : Color.dsTextSecondary)
            HStack(spacing: 3) {
                Text("现价").foregroundStyle(Color.dsTextTertiary)
                Text(GlobalFmt.value(bar.close)).foregroundStyle(Sem.change(pct))
            }
            HStack(spacing: 3) {
                Text("涨跌").foregroundStyle(Color.dsTextTertiary)
                Text(Fmt.pct(pct)).foregroundStyle(Sem.change(pct))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .regular).monospacedDigit())
        .lineLimit(1)
    }

    // MARK: - K 线图

    private func candleChart(_ bars: [GlobalIndexBar]) -> some View {
        let first = bars[0].close
        let last = bars[bars.count - 1].close
        let lo = bars.map(\.low).min() ?? first
        let hi = bars.map(\.high).max() ?? first
        let pad = max((hi - lo) * 0.06, hi * 0.001)
        let domain = (lo - pad)...(hi + pad)
        let focus = hoverDate.flatMap { Self.nearest(bars, to: $0) }
        let longRange = bars.count > 120
        let tab = env.globalMarkets.chartTab

        return VStack(alignment: .leading, spacing: 6) {
            candleReadout(focus ?? bars[bars.count - 1], base: first, last: last, hovering: focus != nil)

            Chart {
                ForEach(bars) { b in
                    let up = b.close >= b.open
                    let c = up ? Sem.up : Sem.down
                    let bodyLo = min(b.open, b.close)
                    let bodyHi = max(b.open, b.close)
                    // 平盘时给一点点高度，否则 BarMark 看不见实体。
                    let bodyTop = bodyHi > bodyLo ? bodyHi : bodyLo + max((hi - lo) * 0.001, 0.01)
                    RuleMark(
                        x: .value("日期", b.date),
                        yStart: .value("低", b.low),
                        yEnd: .value("高", b.high)
                    )
                    .foregroundStyle(c)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    BarMark(
                        x: .value("日期", b.date),
                        yStart: .value("开", bodyLo),
                        yEnd: .value("收", bodyTop)
                    )
                    .foregroundStyle(c)
                }
                if let focus {
                    RuleMark(x: .value("日期", focus.date))
                        .foregroundStyle(Color.dsTextTertiary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                }
            }
            .chartYScale(domain: domain)
            .chartXSelection(value: $hoverDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(Color.dsBorder.opacity(0.3))
                    AxisValueLabel(format: axisFormat(tab: tab, longRange: longRange))
                        .foregroundStyle(Color.dsTextTertiary)
                        .font(.dsMicro())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.dsBorder.opacity(0.3))
                    AxisValueLabel()
                        .foregroundStyle(Color.dsTextTertiary)
                        .font(.dsMicro())
                }
            }
        }
    }

    private func axisFormat(tab: GlobalMarketStore.ChartTab, longRange: Bool) -> Date.FormatStyle {
        switch tab {
        case .month:
            return .dateTime.year().month()
        case .week:
            return longRange ? .dateTime.year(.twoDigits).month(.twoDigits) : .dateTime.month(.twoDigits).day()
        default:
            return longRange ? .dateTime.year(.twoDigits).month(.twoDigits) : .dateTime.month(.twoDigits).day()
        }
    }

    private func candleReadout(_ bar: GlobalIndexBar, base: Double, last: Double, hovering: Bool) -> some View {
        let pct = base > 0 ? (bar.close / base - 1) * 100 : nil
        let barPct = bar.open > 0 ? (bar.close / bar.open - 1) * 100 : nil
        return HStack(spacing: 12) {
            Text(Self.dayText(bar.date))
                .foregroundStyle(hovering ? Color.dsTextPrimary : Color.dsTextSecondary)
            readoutItem("开", bar.open)
            readoutItem("高", bar.high)
            readoutItem("低", bar.low)
            readoutItem("收", bar.close)
            HStack(spacing: 3) {
                Text("涨跌").foregroundStyle(Color.dsTextTertiary)
                Text(Fmt.pct(barPct)).foregroundStyle(Sem.change(barPct))
            }
            if !hovering {
                HStack(spacing: 3) {
                    Text("区间").foregroundStyle(Color.dsTextTertiary)
                    Text(Fmt.pct(base > 0 ? (last / base - 1) * 100 : nil)).foregroundStyle(Sem.change(pct))
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .regular).monospacedDigit())
        .lineLimit(1)
    }

    private func readoutItem(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(Color.dsTextTertiary)
            Text(GlobalFmt.value(value)).foregroundStyle(Color.dsTextPrimary)
        }
    }

    private var readOnlyNote: some View {
        let trading = env.globalMarkets.anyTrading
        return HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text(trading
                 ? "交易中报价约每 3 秒刷新；分时约每 15 秒更新。指数不可直接买卖。"
                 : "当前无开市市场，报价约每 20 秒刷新。指数不可直接买卖。")
            Spacer(minLength: 0)
        }
        .font(.dsMicro())
        .foregroundStyle(Color.dsTextTertiary)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    // MARK: - 工具

    private static func nearest(_ bars: [GlobalIndexBar], to date: Date) -> GlobalIndexBar? {
        bars.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private static func localTime(_ date: Date, timeZone: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: timeZone)
        f.dateFormat = "EEE HH:mm"
        return f.string(from: date)
    }

    private static func dayText(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func minuteText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private static func sessionText(_ session: GlobalIndex.Session) -> String {
        func hm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
        return session.ranges.map { "\(hm($0.lowerBound))–\(hm($0.upperBound))" }.joined(separator: "，")
    }
}
