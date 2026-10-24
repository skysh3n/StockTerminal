import SwiftUI
import DesignSystem
import TradingCore

/// 「榜单」工作区左栏：涨跌幅/成交额/涨停/龙虎榜。与自选完全分离。
struct MarketBoardsPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let board = env.marketBoard
        VStack(spacing: 0) {
            PanelHeader(headerTitle) {
                headerTrailing
            }
            modeStrip
            Rectangle().fill(Color.dsBorder.opacity(0.7)).frame(height: 0.5)
            switch board.listMode {
            case .gainers, .losers, .turnover, .turnoverRate, .amplitude:
                RankListPanel()
            case .limitUp:
                LimitUpListPanel()
            case .limitDown:
                LimitDownListPanel()
            case .billboard:
                BillboardListPanel()
            }
        }
    }

    private var headerTitle: String {
        switch env.marketBoard.listMode {
        case .gainers: return "涨幅榜"
        case .losers: return "跌幅榜"
        case .turnover: return "成交额榜"
        case .turnoverRate: return "换手榜"
        case .amplitude: return "振幅榜"
        case .limitUp: return "涨停池"
        case .limitDown: return "跌停池"
        case .billboard: return "龙虎榜"
        }
    }

    @ViewBuilder
    private var headerTrailing: some View {
        let board = env.marketBoard
        if (board.listMode.isStockRanking && board.rankingLoading)
            || (board.listMode.isLimitUp && board.limitUpLoading)
            || (board.listMode.isLimitDown && board.limitDownLoading)
            || (board.listMode.isBillboard && board.billboardLoading) {
            ProgressView().controlSize(.mini)
        } else {
            let n: Int = {
                switch board.listMode {
                case .gainers, .losers, .turnover, .turnoverRate, .amplitude: return board.ranking.count
                case .limitUp: return board.limitUp.count
                case .limitDown: return board.limitDown.count
                case .billboard: return board.billboard.count
                }
            }()
            Tag(text: "\(n)", color: .dsTextSecondary)
        }
    }

    private var modeStrip: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(BoardListMode.allCases) { mode in
                        let active = env.marketBoard.listMode == mode
                        Button {
                            env.setBoardMode(mode)
                        } label: {
                            Text(mode.label)
                                .font(.dsMicro(medium: active))
                                .foregroundStyle(active ? Color.dsAccent : Color.dsTextTertiary)
                                .padding(.horizontal, 7)
                                .frame(height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(active ? Color.dsAccent.opacity(0.14) : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.dsElevated.opacity(0.8)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.dsBorder, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .help("刷新")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private func refresh() {
        Task { await env.marketBoard.applyMode(env.marketBoard.listMode) }
    }
}

/// 龙虎榜列表。
struct BillboardListPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let board = env.marketBoard
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("代码 / 名称").tracking(0.3)
                Spacer(minLength: 2)
                Text("净买额").tracking(0.3).frame(width: 66, alignment: .trailing)
                Text("涨跌幅").tracking(0.3).frame(width: 56, alignment: .trailing)
            }
            .font(.dsMicro())
            .foregroundStyle(Color.dsTextTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)

            if board.billboardLoading && board.billboard.isEmpty {
                EmptyHint(text: "加载龙虎榜…")
            } else if board.billboard.isEmpty {
                EmptyHint(text: board.billboardError ?? "暂无龙虎榜数据")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(board.billboard) { item in
                            billboardRow(item)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                                .onTapGesture { env.selectMarketSymbol(item.symbol) }
                                .contextMenu {
                                    Button("加入当前自选板块") {
                                        env.selectMarketSymbol(item.symbol, addToWatchlist: true)
                                    }
                                }
                                .help(item.explanation.isEmpty ? item.tradeDate : item.explanation)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func billboardRow(_ item: BillboardEntry) -> some View {
        let color = Sem.change(item.changePercent)
        let netColor = Sem.change(item.netAmount.doubleValue)
        return HStack(spacing: 6) {
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

            Text(Fmt.amount(item.netAmount))
                .font(.dsCallout(medium: true))
                .foregroundStyle(netColor)
                .frame(width: 66, alignment: .trailing)

            ChangeChip(text: Fmt.pct(item.changePercent), color: color, compact: true)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .rowHover(selected: env.watchlist.selectedCode == item.symbol.fullCode, radius: 6)
    }
}
