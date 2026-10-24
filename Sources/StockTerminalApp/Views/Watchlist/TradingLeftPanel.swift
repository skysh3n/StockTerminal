import SwiftUI
import DesignSystem
import TradingCore

/// 交易左栏：自选 | 榜单 切换（标题放大）。
struct TradingLeftPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            modeHeader
            Rectangle().fill(Color.dsBorder.opacity(0.7)).frame(height: 0.5)
            Group {
                switch env.leftPanelMode {
                case .watchlist:
                    WatchlistPanel(embedded: true)
                case .boards:
                    LeftBoardsPanel()
                }
            }
        }
        .onChange(of: env.leftPanelMode) { _, mode in
            if mode == .boards {
                Task { await env.marketBoard.applyMode(env.marketBoard.listMode) }
            }
        }
    }

    private var modeHeader: some View {
        let mode = env.leftPanelMode
        let count: String = {
            switch mode {
            case .watchlist: return "\(env.watchlist.codes.count)"
            case .boards: return "\(activeBoardCount)"
            }
        }()
        return HStack(spacing: 8) {
            UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 1,
                                   bottomTrailingRadius: 1, topTrailingRadius: 1)
                .fill(Color.dsAccent.opacity(0.85))
                .frame(width: 2.5, height: 14)

            HStack(spacing: 2) {
                ForEach(AppEnvironment.LeftPanelMode.allCases) { m in
                    let on = mode == m
                    Button {
                        env.leftPanelMode = m
                    } label: {
                        Text(m.title)
                            .font(.dsCallout(medium: true))
                            .tracking(0.2)
                            .foregroundStyle(on ? Color.dsTextPrimary : Color.dsTextTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(on ? Color.dsAccent.opacity(0.12) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
            Tag(text: count, color: .dsTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var activeBoardCount: Int {
        let b = env.marketBoard
        switch b.listMode {
        case .gainers, .losers, .turnover, .turnoverRate, .amplitude: return b.ranking.count
        case .industry, .concept:
            return b.activeSector == nil ? b.sectors.count : b.sectorConstituents.count
        case .limitUp: return b.limitUp.count
        case .limitDown: return b.limitDown.count
        case .billboard: return b.billboard.count
        }
    }
}

/// 左栏榜单：与自选「板块」相同的芯片条 + 列表表头/行密度；点芯片切换榜种。
struct LeftBoardsPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let board = env.marketBoard
        VStack(spacing: 0) {
            boardChipStrip
            Rectangle().fill(Color.dsBorder.opacity(0.7)).frame(height: 0.5)
            switch board.listMode {
            case .gainers, .losers, .turnover, .turnoverRate, .amplitude:
                RankListPanel()
            case .industry, .concept:
                SectorListPanel()
            case .limitUp:
                LimitUpListPanel()
            case .limitDown:
                LimitDownListPanel()
            case .billboard:
                BillboardListPanel()
            }
        }
        .task {
            await env.marketBoard.applyMode(env.marketBoard.listMode)
        }
    }

    private var boardChipStrip: some View {
        let active = env.marketBoard.listMode
        return HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(BoardListMode.allCases) { mode in
                        modeChip(mode, active: mode == active)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            Button {
                Task { await env.marketBoard.applyMode(env.marketBoard.listMode) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.dsElevated.opacity(0.8)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.dsBorder, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .help("刷新当前榜")
            .padding(.trailing, 8)
        }
    }

    private func modeChip(_ mode: BoardListMode, active: Bool) -> some View {
        Button {
            env.setBoardMode(mode)
        } label: {
            Text(mode.label)
                .font(.dsMicro(medium: active))
                .lineLimit(1)
                .foregroundStyle(active ? Color.dsTextPrimary : Color.dsTextTertiary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.dsAccent.opacity(0.16) : Color.dsElevated.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(active ? Color.dsAccent.opacity(0.45) : Color.dsBorder, lineWidth: 0.6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
