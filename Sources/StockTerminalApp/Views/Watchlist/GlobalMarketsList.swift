import SwiftUI
import DesignSystem
import TradingCore

/// 左栏「全球」看板：按亚太 / 欧洲 / 美洲分组的主要股指，只读。
struct GlobalMarketsList: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let store = env.globalMarkets
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("指数 / 市场").tracking(0.3)
                Spacer(minLength: 2)
                Text("现价").tracking(0.3).frame(width: 76, alignment: .trailing)
                Text("涨跌幅").tracking(0.3).frame(width: 62, alignment: .trailing)
            }
            .font(.dsMicro())
            .foregroundStyle(Color.dsTextTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)

            ScrollView {
                LazyVStack(spacing: 1, pinnedViews: [.sectionHeaders]) {
                    ForEach(GlobalIndex.Region.allCases, id: \.self) { region in
                        let items = store.indices(in: region)
                        Section {
                            ForEach(items) { index in
                                GlobalIndexRow(
                                    index: index,
                                    quote: store.quotes[index.id],
                                    trading: index.isTrading(at: store.now)
                                )
                                .padding(.horizontal, 6)
                            }
                        } header: {
                            regionHeader(region, open: items.filter { $0.isTrading(at: store.now) }.count)
                        }
                    }
                }
                .padding(.bottom, 4)
            }

            Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)
            footer(store)
        }
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
    }

    private func regionHeader(_ region: GlobalIndex.Region, open: Int) -> some View {
        HStack(spacing: 6) {
            Text(region.rawValue)
                .font(.dsMicro(medium: true))
                .tracking(0.5)
                .foregroundStyle(Color.dsTextSecondary)
            Spacer(minLength: 0)
            Text(open > 0 ? "\(open) 个市场交易中" : "全部休市")
                .font(.dsMicro())
                .foregroundStyle(open > 0 ? Color.dsAccent : Color.dsTextTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 3)
        .background(Color.dsPanel)
    }

    private func footer(_ store: GlobalMarketStore) -> some View {
        HStack(spacing: 4) {
            if let updated = store.lastUpdated {
                Text("更新于 \(Fmt.clock(updated)) · 每 15 秒刷新")
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

private struct GlobalIndexRow: View {
    let index: GlobalIndex
    let quote: GlobalIndexQuote?
    let trading: Bool

    var body: some View {
        let color = Sem.change(quote?.changePercent)
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(index.name)
                    .font(.dsBody(medium: true))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(trading ? Color.dsAccent : Color.dsTextTertiary.opacity(0.6))
                        .frame(width: 5, height: 5)
                    Text("\(index.market) · \(trading ? "交易中" : "休市")")
                        .font(.dsMicro())
                        .tracking(0.2)
                        .foregroundStyle(trading ? Color.dsTextSecondary : Color.dsTextTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1.5) {
                Text(quote.map { String(format: "%.2f", $0.last) } ?? "--")
                    .font(.dsCallout(medium: true))
                    .tracking(-0.1)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(quote.map { String(format: "%+.2f", $0.change) } ?? "--")
                    .font(.dsMicro())
                    .foregroundStyle(color.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(width: 76, alignment: .trailing)

            ChangeChip(text: Fmt.pct(quote?.changePercent), color: color, compact: true)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .rowHover(radius: 6)
        .help(rangeText)
    }

    private var rangeText: String {
        guard let quote, let high = quote.high, let low = quote.low else { return index.name }
        return "\(index.name)  最高 \(String(format: "%.2f", high))  最低 \(String(format: "%.2f", low))"
    }
}
