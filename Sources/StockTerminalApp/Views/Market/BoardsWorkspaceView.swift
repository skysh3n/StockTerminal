import SwiftUI
import DesignSystem
import TradingCore

/// 「榜单」全屏工作区：多榜分块，块内可滚动；点股票进个股详情，可加自选。
struct BoardsWorkspaceView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var sectorSheet: SectorBoard?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        let board = env.marketBoard
        VStack(spacing: 0) {
            IndexStrip()
            HStack(spacing: 10) {
                Text("市场榜单")
                    .font(.dsTitle())
                    .foregroundStyle(Color.dsTextPrimary)
                Text("点股票进入详情 · 右键或「+」加自选")
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
                Spacer(minLength: 0)
                if board.overviewLoading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await board.refreshOverview() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.dsTextSecondary)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.dsElevated.opacity(0.9)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.dsBorder, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .help("刷新全部榜单")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    rankBlock(title: "涨幅榜", accent: Sem.up, items: board.gainers, metric: .change)
                    rankBlock(title: "跌幅榜", accent: Sem.down, items: board.losers, metric: .change)
                    rankBlock(title: "成交额", accent: Color.dsAccent, items: board.turnoverBoard, metric: .turnover)
                    rankBlock(title: "换手率", accent: Color.dsAccent, items: board.turnoverRateBoard, metric: .turnoverRate)
                    rankBlock(title: "振幅榜", accent: Color.dsTextSecondary, items: board.amplitudeBoard, metric: .amplitude)
                    rankBlock(title: "涨停池", accent: Sem.up, items: board.limitUp, metric: .change)
                    rankBlock(title: "跌停池", accent: Sem.down, items: board.limitDown, metric: .change)
                    sectorBlock(title: "行业板块", sectors: board.industrySectors)
                    sectorBlock(title: "概念板块", sectors: board.conceptSectors)
                    billboardBlock(items: board.billboard)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
        .task {
            await env.marketBoard.refreshOverview()
        }
        .sheet(item: $sectorSheet) { sector in
            SectorConstituentsSheet(sector: sector)
        }
    }

    private func rankBlock(
        title: String,
        accent: Color,
        items: [MarketRankItem],
        metric: BoardMetric
    ) -> some View {
        BoardBlock(title: title, count: items.count, accent: accent) {
            if items.isEmpty {
                EmptyHint(text: "暂无数据")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            BoardStockRow(
                                index: idx + 1,
                                name: item.symbol.name,
                                code: item.symbol.fullCode,
                                price: item.lastPrice,
                                changePercent: item.changePercent,
                                trailing: metricText(item, metric),
                                selected: env.watchlist.selectedCode == item.symbol.fullCode
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { openDetail(item.symbol) }
                            .contextMenu {
                                Button("查看详情") { openDetail(item.symbol) }
                                Button("加入自选") { addWatch(item.symbol) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectorBlock(title: String, sectors: [SectorBoard]) -> some View {
        BoardBlock(title: title, count: sectors.count, accent: Color.dsAccent) {
            if sectors.isEmpty {
                EmptyHint(text: "暂无板块")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(sectors.enumerated()), id: \.element.id) { idx, s in
                            BoardSectorRow(index: idx + 1, sector: s)
                                .contentShape(Rectangle())
                                .onTapGesture { sectorSheet = s }
                        }
                    }
                }
            }
        }
    }

    private func billboardBlock(items: [BillboardEntry]) -> some View {
        BoardBlock(title: "龙虎榜", count: items.count, accent: Color.dsAccent) {
            if items.isEmpty {
                EmptyHint(text: env.marketBoard.billboardError ?? "暂无龙虎榜")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            BoardStockRow(
                                index: idx + 1,
                                name: item.symbol.name,
                                code: item.symbol.fullCode,
                                price: item.closePrice,
                                changePercent: item.changePercent,
                                trailing: Fmt.amount(item.netAmount),
                                selected: env.watchlist.selectedCode == item.symbol.fullCode
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { openDetail(item.symbol) }
                            .contextMenu {
                                Button("查看详情") { openDetail(item.symbol) }
                                Button("加入自选") { addWatch(item.symbol) }
                            }
                            .help(item.explanation.isEmpty ? item.tradeDate : item.explanation)
                        }
                    }
                }
            }
        }
    }

    private enum BoardMetric { case change, turnover, turnoverRate, amplitude }

    private func metricText(_ item: MarketRankItem, _ metric: BoardMetric) -> String {
        switch metric {
        case .change: return Fmt.pct(item.changePercent)
        case .turnover: return Fmt.amount(item.turnover)
        case .turnoverRate: return String(format: "%.2f%%", item.turnoverRate)
        case .amplitude: return String(format: "%.2f%%", item.amplitude)
        }
    }

    private func openDetail(_ symbol: Symbol) {
        env.workspace = .trading
        env.leftPanelMode = .watchlist
        env.selectMarketSymbol(symbol)
    }

    private func addWatch(_ symbol: Symbol) {
        env.selectMarketSymbol(symbol, addToWatchlist: true)
        env.trading.showToast("已加入自选：\(symbol.name)", isError: false)
    }
}

// MARK: - 块容器

private struct BoardBlock<Content: View>: View {
    let title: String
    let count: Int
    let accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent.opacity(0.9))
                    .frame(width: 3, height: 12)
                Text(title)
                    .font(.dsLabel(medium: true))
                    .tracking(0.4)
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.dsInput))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Rectangle().fill(Color.dsBorder.opacity(0.55)).frame(height: 0.5)

            content
                .frame(height: 280)
        }
        .terminalCard(radius: 10)
    }
}

private struct BoardStockRow: View {
    let index: Int
    let name: String
    let code: String
    let price: Decimal
    let changePercent: Double
    let trailing: String
    let selected: Bool

    var body: some View {
        let color = Sem.change(changePercent)
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.dsMicro(medium: true))
                .foregroundStyle(index <= 3 ? Color.dsAccent : Color.dsTextTertiary)
                .frame(width: 16, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.dsCallout(medium: true))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                Text(code)
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Fmt.price(price))
                .font(.dsCallout(medium: true))
                .foregroundStyle(color)
                .frame(width: 64, alignment: .trailing)

            Text(trailing)
                .font(.dsMicro(medium: true))
                .foregroundStyle(color)
                .frame(width: 62, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .rowHover(selected: selected, radius: 5)
    }
}

private struct BoardSectorRow: View {
    let index: Int
    let sector: SectorBoard

    var body: some View {
        let color = Sem.change(sector.changePercent)
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.dsMicro(medium: true))
                .foregroundStyle(index <= 3 ? Color.dsAccent : Color.dsTextTertiary)
                .frame(width: 16, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(sector.name)
                    .font(.dsCallout(medium: true))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                Text("领涨 \(sector.leadName)")
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.pct(sector.changePercent))
                .font(.dsMicro(medium: true))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .rowHover(selected: false, radius: 5)
    }
}

/// 板块成分股：点开后可进详情 / 加自选。
struct SectorConstituentsSheet: View {
    @Environment(AppEnvironment.self) private var env
    let sector: SectorBoard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sector.name)
                        .font(.dsTitle())
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(Fmt.pct(sector.changePercent))
                        .font(.dsCallout(medium: true))
                        .foregroundStyle(Sem.change(sector.changePercent))
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dsTextSecondary)
            }
            .padding(16)

            Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)

            Group {
                if env.marketBoard.sectorLoading && env.marketBoard.sectorConstituents.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if env.marketBoard.sectorConstituents.isEmpty {
                    EmptyHint(text: env.marketBoard.sectorError ?? "暂无成分股")
                } else {
                    List(env.marketBoard.sectorConstituents) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.symbol.name).font(.dsBody(medium: true))
                                Text(item.symbol.fullCode).font(.dsMicro()).foregroundStyle(Color.dsTextTertiary)
                            }
                            Spacer()
                            Text(Fmt.pct(item.changePercent))
                                .foregroundStyle(Sem.change(item.changePercent))
                            Button("+自选") {
                                env.selectMarketSymbol(item.symbol, addToWatchlist: true)
                                env.trading.showToast("已加入自选：\(item.symbol.name)", isError: false)
                            }
                            .buttonStyle(.plain)
                            .font(.dsMicro(medium: true))
                            .foregroundStyle(Color.dsAccent)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismiss()
                            env.workspace = .trading
                            env.leftPanelMode = .watchlist
                            env.selectMarketSymbol(item.symbol)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .task { await env.marketBoard.openSector(sector) }
    }
}
