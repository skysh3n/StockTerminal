import SwiftUI
import Charts
import DesignSystem
import TradingCore

/// 全球市场总览：按地区分块的指数卡片，带迷你走势，点进详情。
struct GlobalMarketsOverview: View {
    @Environment(AppEnvironment.self) private var env

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 10),
    ]

    var body: some View {
        let store = env.globalMarkets
        VStack(spacing: 0) {
            header(store)
            Rectangle().fill(Color.dsBorder.opacity(0.7)).frame(height: 0.5)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(GlobalIndex.Region.allCases, id: \.self) { region in
                        let items = store.indices(in: region)
                        Section {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(items) { index in
                                    GlobalIndexCard(
                                        index: index,
                                        quote: store.quotes[index.id],
                                        bars: store.sparkBars(for: index.id),
                                        trading: index.isTrading(at: store.now)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { store.select(index.id) }
                                }
                            }
                            .padding(.horizontal, 14)
                        } header: {
                            regionHeader(region, open: items.filter { $0.isTrading(at: store.now) }.count)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 12)
            }

            Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)
            footer(store)
        }
    }

    private func header(_ store: GlobalMarketStore) -> some View {
        let open = store.indices.filter { $0.isTrading(at: store.now) }.count
        return PanelHeader("全球市场") {
            HStack(spacing: 8) {
                Tag(text: "\(store.indices.count) 指数", color: .dsTextSecondary)
                Tag(
                    text: open > 0 ? "\(open) 个交易中" : "全部休市",
                    color: open > 0 ? .dsAccent : .dsTextTertiary
                )
            }
        }
    }

    private func regionHeader(_ region: GlobalIndex.Region, open: Int) -> some View {
        HStack(spacing: 6) {
            Text(region.rawValue)
                .font(.dsLabel(medium: true))
                .tracking(0.5)
                .foregroundStyle(Color.dsTextSecondary)
            Spacer(minLength: 0)
            Text(open > 0 ? "\(open) 个市场交易中" : "全部休市")
                .font(.dsMicro())
                .foregroundStyle(open > 0 ? Color.dsAccent : Color.dsTextTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(Color.dsPanel)
    }

    private func footer(_ store: GlobalMarketStore) -> some View {
        let open = store.indices.filter { $0.isTrading(at: store.now) }.count
        return HStack(spacing: 4) {
            if let updated = store.lastUpdated {
                Text(open > 0
                     ? "更新于 \(Fmt.clock(updated)) · 交易中约 3 秒刷新 · 点击卡片查看分时/K线"
                     : "更新于 \(Fmt.clock(updated)) · 休市约 20 秒刷新 · 点击卡片查看详情")
            } else if store.loading {
                Text("正在获取全球行情…")
            } else {
                Text("全球行情暂不可用，稍后自动重试")
                    .foregroundStyle(Color.dsWarning)
            }
            Spacer(minLength: 0)
        }
        .font(.dsMicro())
        .foregroundStyle(Color.dsTextTertiary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .help("交易状态按各市场常规交易时段估算，不含当地节假日")
    }
}

// MARK: - 指数卡片

private struct GlobalIndexCard: View {
    let index: GlobalIndex
    let quote: GlobalIndexQuote?
    let bars: [GlobalIndexBar]
    let trading: Bool

    var body: some View {
        let color = Sem.change(quote?.changePercent)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(index.name)
                        .font(.dsBody(medium: true))
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(1)
                    MarketStatusLabel(market: index.market, trading: trading)
                }
                Spacer(minLength: 4)
                ChangeChip(text: Fmt.pct(quote?.changePercent), color: color, compact: true)
            }

            Text(GlobalFmt.value(quote?.last))
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .tracking(-0.3)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(GlobalFmt.signed(quote?.change))
                .font(.dsMicro())
                .foregroundStyle(color.opacity(0.85))

            sparkline(color: color)
                .frame(height: 36)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.dsElevated.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.dsBorder.opacity(0.85), lineWidth: 0.6)
        )
        .rowHover(radius: 8)
    }

    @ViewBuilder
    private func sparkline(color: Color) -> some View {
        if bars.count >= 2 {
            let closes = bars.map(\.close)
            let lo = closes.min() ?? 0
            let hi = closes.max() ?? 1
            let pad = max((hi - lo) * 0.08, hi * 0.0005)
            Chart(bars) { bar in
                AreaMark(
                    x: .value("日", bar.date),
                    yStart: .value("底", lo - pad),
                    yEnd: .value("收", bar.close)
                )
                .foregroundStyle(LinearGradient(
                    colors: [color.opacity(0.28), color.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                LineMark(x: .value("日", bar.date), y: .value("收", bar.close))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .chartLegend(.hidden)
            .chartPlotStyle { $0.padding(0) }
            .allowsHitTesting(false)
        } else if index.history == nil {
            Text("仅快照")
                .font(.dsMicro())
                .foregroundStyle(Color.dsTextTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.dsBorder.opacity(0.35))
                .overlay(
                    ProgressView()
                        .controlSize(.mini)
                        .opacity(bars.isEmpty ? 1 : 0)
                )
        }
    }
}

/// 「纽约 · 交易中」小字 + 状态点
struct MarketStatusLabel: View {
    let market: String
    let trading: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(trading ? Color.dsAccent : Color.dsTextTertiary.opacity(0.6))
                .frame(width: 5, height: 5)
            Text("\(market) · \(trading ? "交易中" : "休市")")
                .font(.dsMicro())
                .tracking(0.2)
                .foregroundStyle(trading ? Color.dsTextSecondary : Color.dsTextTertiary)
                .lineLimit(1)
        }
    }
}

/// 指数点位格式化（Double，两位小数）。
enum GlobalFmt {
    static func value(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.2f", v)
    }

    static func signed(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%+.2f", v)
    }
}
