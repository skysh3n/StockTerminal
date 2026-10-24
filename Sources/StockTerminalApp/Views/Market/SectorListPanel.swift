import SwiftUI
import DesignSystem
import TradingCore

/// 左栏行业/概念：板块列表 → 点入成分股（仍走三栏选中切图）。
struct SectorListPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let board = env.marketBoard
        VStack(spacing: 0) {
            if let active = board.activeSector {
                sectorHeader(active)
                stockList(board.sectorConstituents, loading: board.sectorLoading, empty: board.sectorError)
            } else {
                sectorColumns
                sectorRows
            }
        }
    }

    private func sectorHeader(_ active: SectorBoard) -> some View {
        HStack(spacing: 6) {
            Button {
                env.marketBoard.closeSector()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.dsAccent)
            }
            .buttonStyle(.plain)
            .help("返回板块列表")

            Text(active.name)
                .font(.dsMicro(medium: true))
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(1)
            Text(Fmt.pct(active.changePercent))
                .font(.dsMicro())
                .foregroundStyle(Sem.change(active.changePercent))
            Spacer(minLength: 0)
            if env.marketBoard.sectorLoading {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder.opacity(0.55)).frame(height: 0.5)
        }
    }

    private var sectorColumns: some View {
        HStack(spacing: 6) {
            Text("板块").tracking(0.3)
            Spacer(minLength: 2)
            Text("涨跌幅").tracking(0.3).frame(width: 56, alignment: .trailing)
            Text("领涨").tracking(0.3).frame(width: 72, alignment: .trailing)
        }
        .font(.dsMicro())
        .foregroundStyle(Color.dsTextTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var sectorRows: some View {
        let board = env.marketBoard
        if board.sectorLoading && board.sectors.isEmpty {
            EmptyHint(text: "加载板块…")
        } else if board.sectors.isEmpty {
            EmptyHint(text: board.sectorError ?? "暂无板块数据")
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(board.sectors) { s in
                        Button {
                            Task { await env.marketBoard.openSector(s) }
                        } label: {
                            sectorRow(s)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
        }
    }

    private func sectorRow(_ s: SectorBoard) -> some View {
        let color = Sem.change(s.changePercent)
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(s.name)
                    .font(.dsBody(medium: true))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                if s.upCount + s.downCount > 0 {
                    Text("涨\(s.upCount) / 跌\(s.downCount)")
                        .font(.dsMicro())
                        .foregroundStyle(Color.dsTextTertiary)
                } else if !s.leadName.isEmpty {
                    Text("领涨 \(s.leadName)")
                        .font(.dsMicro())
                        .foregroundStyle(Color.dsTextTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ChangeChip(text: Fmt.pct(s.changePercent), color: color, compact: true)
                .frame(width: 56, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 1) {
                Text(s.leadName.isEmpty ? "—" : s.leadName)
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextSecondary)
                    .lineLimit(1)
                if s.leadChangePercent != 0 {
                    Text(Fmt.pct(s.leadChangePercent))
                        .font(.dsMicro())
                        .foregroundStyle(Sem.change(s.leadChangePercent))
                }
            }
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .rowHover(radius: 6)
    }

    @ViewBuilder
    private func stockList(_ items: [MarketRankItem], loading: Bool, empty: String?) -> some View {
        HStack(spacing: 6) {
            Text("代码 / 名称").tracking(0.3)
            Spacer(minLength: 2)
            Text("现价").tracking(0.3).frame(width: 66, alignment: .trailing)
            Text("涨跌幅").tracking(0.3).frame(width: 62, alignment: .trailing)
        }
        .font(.dsMicro())
        .foregroundStyle(Color.dsTextTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)

        if loading && items.isEmpty {
            EmptyHint(text: "加载成分…")
        } else if items.isEmpty {
            EmptyHint(text: empty ?? "暂无成分股")
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(items) { item in
                            RankRowView(
                                item: item,
                                selected: env.watchlist.selectedCode == item.symbol.fullCode,
                                kind: .gainers
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

/// 涨停池列表（与个股榜行样式一致）。
struct LimitUpListPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        limitPoolList(
            loading: env.marketBoard.limitUpLoading,
            items: env.marketBoard.limitUp,
            error: env.marketBoard.limitUpError,
            emptyHint: "暂无涨停/触板标的",
            loadingHint: "加载涨停池…"
        )
    }
}

/// 跌停池列表。
struct LimitDownListPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        limitPoolList(
            loading: env.marketBoard.limitDownLoading,
            items: env.marketBoard.limitDown,
            error: env.marketBoard.limitDownError,
            emptyHint: "暂无跌停/触板标的",
            loadingHint: "加载跌停池…"
        )
    }
}

@MainActor
private func limitPoolList(
    loading: Bool,
    items: [MarketRankItem],
    error: String?,
    emptyHint: String,
    loadingHint: String
) -> some View {
    LimitPoolListBody(
        loading: loading,
        items: items,
        error: error,
        emptyHint: emptyHint,
        loadingHint: loadingHint
    )
}

private struct LimitPoolListBody: View {
    @Environment(AppEnvironment.self) private var env
    let loading: Bool
    let items: [MarketRankItem]
    let error: String?
    let emptyHint: String
    let loadingHint: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("代码 / 名称").tracking(0.3)
                Spacer(minLength: 2)
                Text("现价").tracking(0.3).frame(width: 66, alignment: .trailing)
                Text("涨跌幅").tracking(0.3).frame(width: 62, alignment: .trailing)
            }
            .font(.dsMicro())
            .foregroundStyle(Color.dsTextTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)

            if loading && items.isEmpty {
                EmptyHint(text: loadingHint)
            } else if items.isEmpty {
                EmptyHint(text: error ?? emptyHint)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(items) { item in
                            RankRowView(
                                item: item,
                                selected: env.watchlist.selectedCode == item.symbol.fullCode,
                                kind: .gainers
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
}
