import SwiftUI
import DesignSystem
import TradingCore

/// 交易左栏：自选 | 榜单 切换（标题放大）；榜单为块状可滚动列表，点股票切中栏图。
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
                Task { await env.marketBoard.refreshOverview() }
            }
        }
    }

    private var modeHeader: some View {
        let mode = env.leftPanelMode
        let count: String = {
            switch mode {
            case .watchlist: return "\(env.watchlist.codes.count)"
            case .boards:
                return "\(env.marketBoard.gainers.count + env.marketBoard.losers.count)"
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
}

/// 左栏榜单：纵向多块，块内可滑；点选切图，可加自选。
struct LeftBoardsPanel: View {
    @Environment(AppEnvironment.self) private var env
    @State private var sectorSheet: SectorBoard?

    var body: some View {
        let board = env.marketBoard
        VStack(spacing: 0) {
            HStack {
                Text("市场榜")
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
                Spacer()
                if board.overviewLoading {
                    ProgressView().controlSize(.mini)
                }
                Button {
                    Task { await board.refreshOverview() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.dsTextSecondary)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.dsElevated.opacity(0.8)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.dsBorder, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .help("刷新榜单")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ScrollView {
                VStack(spacing: 10) {
                    leftRankBlock("涨幅榜", Sem.up, board.gainers, .change)
                    leftRankBlock("跌幅榜", Sem.down, board.losers, .change)
                    leftRankBlock("成交额", Color.dsAccent, board.turnoverBoard, .turnover)
                    leftRankBlock("换手率", Color.dsAccent, board.turnoverRateBoard, .turnoverRate)
                    leftRankBlock("振幅榜", Color.dsTextSecondary, board.amplitudeBoard, .amplitude)
                    leftRankBlock("涨停池", Sem.up, board.limitUp, .change)
                    leftRankBlock("跌停池", Sem.down, board.limitDown, .change)
                    leftSectorBlock("行业", board.industrySectors)
                    leftSectorBlock("概念", board.conceptSectors)
                    leftBillboard(board.billboard)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .task { await env.marketBoard.refreshOverview() }
        .sheet(item: $sectorSheet) { sector in
            SectorConstituentsSheet(sector: sector)
        }
    }

    private enum Metric { case change, turnover, turnoverRate, amplitude }

    private func leftRankBlock(_ title: String, _ accent: Color, _ items: [MarketRankItem], _ metric: Metric) -> some View {
        leftBlock(title: title, count: items.count, accent: accent) {
            if items.isEmpty {
                Text("暂无数据")
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ForEach(Array(items.prefix(12).enumerated()), id: \.element.id) { idx, item in
                    row(
                        index: idx + 1,
                        name: item.symbol.name,
                        code: item.symbol.fullCode,
                        price: item.lastPrice,
                        pct: item.changePercent,
                        trailing: metricText(item, metric)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { env.selectMarketSymbol(item.symbol) }
                    .contextMenu {
                        Button("加入自选") {
                            env.selectMarketSymbol(item.symbol, addToWatchlist: true)
                            env.trading.showToast("已加入自选：\(item.symbol.name)", isError: false)
                        }
                    }
                }
            }
        }
    }

    private func leftSectorBlock(_ title: String, _ sectors: [SectorBoard]) -> some View {
        leftBlock(title: title, count: sectors.count, accent: Color.dsAccent) {
            if sectors.isEmpty {
                Text("暂无板块")
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ForEach(Array(sectors.prefix(10).enumerated()), id: \.element.id) { idx, s in
                    HStack(spacing: 6) {
                        Text("\(idx + 1)")
                            .font(.dsMicro(medium: true))
                            .foregroundStyle(idx < 3 ? Color.dsAccent : Color.dsTextTertiary)
                            .frame(width: 14, alignment: .trailing)
                        Text(s.name)
                            .font(.dsCallout(medium: true))
                            .foregroundStyle(Color.dsTextPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(Fmt.pct(s.changePercent))
                            .font(.dsMicro(medium: true))
                            .foregroundStyle(Sem.change(s.changePercent))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .onTapGesture { sectorSheet = s }
                }
            }
        }
    }

    private func leftBillboard(_ items: [BillboardEntry]) -> some View {
        leftBlock(title: "龙虎榜", count: items.count, accent: Color.dsAccent) {
            if items.isEmpty {
                Text(env.marketBoard.billboardError ?? "暂无龙虎榜")
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ForEach(Array(items.prefix(10).enumerated()), id: \.element.id) { idx, item in
                    row(
                        index: idx + 1,
                        name: item.symbol.name,
                        code: item.symbol.fullCode,
                        price: item.closePrice,
                        pct: item.changePercent,
                        trailing: Fmt.amount(item.netAmount)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { env.selectMarketSymbol(item.symbol) }
                    .contextMenu {
                        Button("加入自选") {
                            env.selectMarketSymbol(item.symbol, addToWatchlist: true)
                        }
                    }
                }
            }
        }
    }

    private func leftBlock<Content: View>(
        title: String, count: Int, accent: Color, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent.opacity(0.9))
                    .frame(width: 2.5, height: 11)
                Text(title)
                    .font(.dsLabel(medium: true))
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
                Text("\(count)")
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            Rectangle().fill(Color.dsBorder.opacity(0.45)).frame(height: 0.5)
            content()
                .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.dsElevated.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.dsBorder.opacity(0.65), lineWidth: 0.6)
        )
    }

    private func row(
        index: Int, name: String, code: String, price: Decimal, pct: Double, trailing: String
    ) -> some View {
        let color = Sem.change(pct)
        return HStack(spacing: 6) {
            Text("\(index)")
                .font(.dsMicro(medium: true))
                .foregroundStyle(index <= 3 ? Color.dsAccent : Color.dsTextTertiary)
                .frame(width: 14, alignment: .trailing)
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
                .font(.dsMicro(medium: true))
                .foregroundStyle(color)
            Text(trailing)
                .font(.dsMicro(medium: true))
                .foregroundStyle(color)
                .frame(width: 52, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .rowHover(selected: env.watchlist.selectedCode == code, radius: 4)
    }

    private func metricText(_ item: MarketRankItem, _ metric: Metric) -> String {
        switch metric {
        case .change: return Fmt.pct(item.changePercent)
        case .turnover: return Fmt.amount(item.turnover)
        case .turnoverRate: return String(format: "%.1f%%", item.turnoverRate)
        case .amplitude: return String(format: "%.1f%%", item.amplitude)
        }
    }
}
