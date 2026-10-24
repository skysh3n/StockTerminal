import SwiftUI
import DesignSystem
import TradingCore

/// 左栏全市场榜单（涨幅 / 跌幅 / 成交额），点选切图；右键可加入当前自选板块。
struct RankListPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let board = env.marketBoard
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("代码 / 名称").tracking(0.3)
                Spacer(minLength: 2)
                Text(rankSecondaryHeader(board.rankingKind))
                    .tracking(0.3)
                    .frame(width: 66, alignment: .trailing)
                Text("涨跌幅").tracking(0.3).frame(width: 62, alignment: .trailing)
            }
            .font(.dsMicro())
            .foregroundStyle(Color.dsTextTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)

            if board.rankingLoading && board.ranking.isEmpty {
                EmptyHint(text: "加载榜单…")
            } else if board.ranking.isEmpty {
                EmptyHint(text: board.rankingError ?? "暂无榜单数据")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(board.ranking) { item in
                            RankRowView(
                                item: item,
                                selected: env.watchlist.selectedCode == item.symbol.fullCode,
                                kind: board.rankingKind
                            )
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                            .onTapGesture { env.selectMarketSymbol(item.symbol) }
                            .contextMenu {
                                Button("加入当前板块") {
                                    env.selectMarketSymbol(item.symbol, addToWatchlist: true)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func rankSecondaryHeader(_ kind: MarketRankKind) -> String {
        switch kind {
        case .turnover: return "成交额"
        case .turnoverRate: return "换手"
        case .amplitude: return "振幅"
        case .gainers, .losers: return "现价"
        }
    }
}

struct RankRowView: View {
    let item: MarketRankItem
    let selected: Bool
    let kind: MarketRankKind

    var body: some View {
        let color = Sem.change(item.changePercent)
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.symbol.name)
                    .font(.dsBody(medium: true))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                Text(item.symbol.fullCode)
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1.5) {
                switch kind {
                case .turnover:
                    Text(Fmt.amount(item.turnover))
                        .font(.dsCallout(medium: true))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(Fmt.price(item.lastPrice))
                        .font(.dsMicro())
                        .foregroundStyle(color.opacity(0.85))
                case .turnoverRate:
                    Text(String(format: "%.2f%%", item.turnoverRate))
                        .font(.dsCallout(medium: true))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(Fmt.price(item.lastPrice))
                        .font(.dsMicro())
                        .foregroundStyle(color.opacity(0.85))
                case .amplitude:
                    Text(String(format: "%.2f%%", item.amplitude))
                        .font(.dsCallout(medium: true))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(Fmt.price(item.lastPrice))
                        .font(.dsMicro())
                        .foregroundStyle(color.opacity(0.85))
                case .gainers, .losers:
                    Text(Fmt.price(item.lastPrice))
                        .font(.dsCallout(medium: true))
                        .foregroundStyle(color)
                    Text(Fmt.signed(item.change))
                        .font(.dsMicro())
                        .foregroundStyle(color.opacity(0.8))
                }
            }
            .frame(width: 66, alignment: .trailing)

            ChangeChip(text: Fmt.pct(item.changePercent), color: color, compact: true)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .rowHover(selected: selected, radius: 6)
    }
}
