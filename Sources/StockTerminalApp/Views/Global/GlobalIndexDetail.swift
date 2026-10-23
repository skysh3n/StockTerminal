import SwiftUI
import Charts
import DesignSystem
import TradingCore

/// 指数详情：行情概览 + 关键统计 + 日线走势。指数不可交易，因此不放任何下单入口。
struct GlobalIndexDetail: View {
    @Environment(AppEnvironment.self) private var env
    @State private var hoverDate: Date?

    var body: some View {
        let store = env.globalMarkets
        if let index = store.selected {
            let quote = store.quotes[index.id]
            let all = store.history[index.id] ?? []
            let bars = Array(all.suffix(store.range.days))
            VStack(alignment: .leading, spacing: 0) {
                backBar
                Rectangle().fill(Color.dsBorder.opacity(0.6)).frame(height: 0.5)
                header(index, quote: quote, now: store.now)
                Rectangle().fill(Color.dsBorder.opacity(0.6)).frame(height: 0.5)
                stats(quote: quote, all: all, bars: bars, range: store.range)
                Rectangle().fill(Color.dsBorder.opacity(0.6)).frame(height: 0.5)
                chartSection(index, bars: bars, loading: store.historyLoading.contains(index.id))
                Rectangle().fill(Color.dsBorder.opacity(0.6)).frame(height: 0.5)
                readOnlyNote
            }
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
    }

    // MARK: - 统计

    private func stats(quote: GlobalIndexQuote?, all: [GlobalIndexBar], bars: [GlobalIndexBar], range: GlobalMarketStore.Range) -> some View {
        let year = all.suffix(250)
        let amplitude: Double? = {
            guard let q = quote, let h = q.high, let l = q.low, let pre = q.preClose, pre > 0 else { return nil }
            return (h - l) / pre * 100
        }()
        let rangeChange: Double? = {
            guard let first = bars.first?.close, let last = bars.last?.close, first > 0 else { return nil }
            return (last / first - 1) * 100
        }()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 4)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            stat("昨收", GlobalFmt.value(quote?.preClose))
            stat("今开", GlobalFmt.value(quote?.open), color: priceColor(quote?.open, ref: quote?.preClose))
            stat("最高", GlobalFmt.value(quote?.high), color: priceColor(quote?.high, ref: quote?.preClose))
            stat("最低", GlobalFmt.value(quote?.low), color: priceColor(quote?.low, ref: quote?.preClose))
            stat("振幅", amplitude.map { String(format: "%.2f%%", $0) } ?? "--")
            stat("近\(range.rawValue)涨跌", Fmt.pct(rangeChange), color: Sem.change(rangeChange))
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

    // MARK: - 走势

    private func chartSection(_ index: GlobalIndex, bars: [GlobalIndexBar], loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("日线走势")
                    .font(.dsLabel(medium: true))
                    .tracking(0.5)
                    .foregroundStyle(Color.dsTextSecondary)
                Spacer(minLength: 8)
                if index.history != nil {
                    ForEach(GlobalMarketStore.Range.allCases) { r in
                        rangeButton(r)
                    }
                }
            }

            Group {
                if index.history == nil {
                    EmptyHint(text: "该指数暂无历史日线，仅提供实时快照")
                } else if bars.count >= 2 {
                    chart(bars)
                } else if loading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyHint(text: "日线暂时获取失败，稍后重新选择即可重试")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity)
    }

    private func rangeButton(_ r: GlobalMarketStore.Range) -> some View {
        let store = env.globalMarkets
        let selected = store.range == r
        return Button {
            store.range = r
        } label: {
            Text(r.rawValue)
                .font(.dsMicro(medium: selected))
                .foregroundStyle(selected ? Color.dsAccent : Color.dsTextTertiary)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Color.dsAccent.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chart(_ bars: [GlobalIndexBar]) -> some View {
        let first = bars[0].close
        let trendColor = Sem.change(bars[bars.count - 1].close - first)
        let lo = bars.map(\.low).min() ?? first
        let hi = bars.map(\.high).max() ?? first
        let pad = max((hi - lo) * 0.06, hi * 0.001)
        let domain = (lo - pad)...(hi + pad)
        let focus = hoverDate.flatMap { Self.nearest(bars, to: $0) }
        let longRange = bars.count > 260

        return VStack(alignment: .leading, spacing: 6) {
            readout(focus ?? bars[bars.count - 1], base: first, hovering: focus != nil)

            Chart {
                ForEach(bars) { b in
                    AreaMark(
                        x: .value("日期", b.date),
                        yStart: .value("基线", domain.lowerBound),
                        yEnd: .value("收盘", b.close)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [trendColor.opacity(0.22), trendColor.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    LineMark(x: .value("日期", b.date), y: .value("收盘", b.close))
                        .foregroundStyle(trendColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                }
                if let focus {
                    RuleMark(x: .value("日期", focus.date))
                        .foregroundStyle(Color.dsTextTertiary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    PointMark(x: .value("日期", focus.date), y: .value("收盘", focus.close))
                        .symbolSize(36)
                        .foregroundStyle(trendColor)
                }
            }
            .chartYScale(domain: domain)
            .chartXSelection(value: $hoverDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(Color.dsBorder.opacity(0.35))
                    AxisValueLabel(format: longRange
                                   ? .dateTime.year(.twoDigits).month(.twoDigits)
                                   : .dateTime.month(.twoDigits).day(.twoDigits))
                        .foregroundStyle(Color.dsTextTertiary)
                        .font(.dsMicro())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.dsBorder.opacity(0.35))
                    AxisValueLabel()
                        .foregroundStyle(Color.dsTextTertiary)
                        .font(.dsMicro())
                }
            }
        }
    }

    private func readout(_ bar: GlobalIndexBar, base: Double, hovering: Bool) -> some View {
        let pct = base > 0 ? (bar.close / base - 1) * 100 : nil
        return HStack(spacing: 12) {
            Text(Self.dayText(bar.date))
                .foregroundStyle(hovering ? Color.dsTextPrimary : Color.dsTextSecondary)
            readoutItem("开", bar.open)
            readoutItem("高", bar.high)
            readoutItem("低", bar.low)
            readoutItem("收", bar.close)
            HStack(spacing: 3) {
                Text("较区间起点").foregroundStyle(Color.dsTextTertiary)
                Text(Fmt.pct(pct)).foregroundStyle(Sem.change(pct))
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
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text("指数反映市场整体表现，不能直接买卖。交易状态按常规时段估算，不含当地节假日。")
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

    private static func sessionText(_ session: GlobalIndex.Session) -> String {
        func hm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
        return session.ranges.map { "\(hm($0.lowerBound))–\(hm($0.upperBound))" }.joined(separator: "，")
    }
}
