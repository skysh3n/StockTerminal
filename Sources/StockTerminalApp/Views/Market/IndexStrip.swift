import SwiftUI
import DesignSystem
import TradingCore

/// 交易工作区顶栏下的指数条：横向滚动，点 A 股指数切图；全球指数进「全球」详情。
struct IndexStrip: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(AShareIndices.all.enumerated()), id: \.element.fullCode) { idx, symbol in
                        if idx > 0 { divider }
                        aShareCell(symbol)
                    }
                    ForEach(StripGlobalIndices.items) { index in
                        divider
                        globalCell(index)
                    }
                }
                .padding(.trailing, 8)
            }
            sessionHint
                .padding(.leading, 6)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Color.dsPanel.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder.opacity(0.6)).frame(height: 0.5)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.dsBorder.opacity(0.7))
            .frame(width: 0.5, height: 22)
    }

    private func aShareCell(_ symbol: Symbol) -> some View {
        let q = env.marketBoard.indexQuotes[symbol.fullCode]
            ?? env.market.states[symbol.fullCode]?.quote
        let selected = env.watchlist.selectedCode == symbol.fullCode
        let color = Sem.change(q?.changePercent)
        return Button {
            env.leftPanelMode = .watchlist
            env.selectMarketSymbol(symbol)
        } label: {
            cellLabel(
                title: shortName(symbol.name),
                price: Fmt.price(q?.lastPrice),
                pct: Fmt.pct(q?.changePercent),
                color: color,
                selected: selected
            )
        }
        .buttonStyle(PressableStyle())
        .help("\(symbol.name) \(symbol.fullCode) — 点击看盘")
    }

    private func globalCell(_ index: GlobalIndex) -> some View {
        let q = env.marketBoard.stripGlobalQuotes[index.id]
            ?? env.globalMarkets.quotes[index.id]
        let selected = env.workspace == .global && env.globalMarkets.selectedID == index.id
        let color = Sem.change(q?.changePercent)
        return Button {
            env.workspace = .global
            env.globalMarkets.select(index.id)
        } label: {
            cellLabel(
                title: shortGlobalName(index.name),
                price: q.map { Fmt.price(Decimal($0.last)) } ?? "--",
                pct: q.map { Fmt.pct($0.changePercent) } ?? "--",
                color: color,
                selected: selected
            )
        }
        .buttonStyle(PressableStyle())
        .help("\(index.name) — 打开全球详情")
    }

    private func cellLabel(title: String, price: String, pct: String, color: Color, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.dsMicro(medium: true))
                .foregroundStyle(selected ? Color.dsAccent : Color.dsTextSecondary)
            Text(price)
                .font(.dsFootnote(medium: true))
                .foregroundStyle(color)
            Text(pct)
                .font(.dsMicro())
                .foregroundStyle(color.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.dsAccent.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var sessionHint: some View {
        let phase = MarketSession.phase()
        let active = phase.isActiveTrading
        return Text(phase.shortLabel)
            .font(.dsMicro())
            .tracking(0.3)
            .foregroundStyle(active ? Color.dsDown : Color.dsTextTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.dsElevated.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.dsBorder, lineWidth: 0.5))
            .help(phase.label)
    }

    private func shortName(_ name: String) -> String {
        if name.hasSuffix("指数") { return String(name.dropLast(2)) }
        if name.hasSuffix("指") { return String(name.dropLast(1)) }
        return name
    }

    private func shortGlobalName(_ name: String) -> String {
        switch name {
        case "恒生指数": return "恒生"
        case "恒生科技": return "恒科"
        case "纳斯达克": return "纳指"
        case "道琼斯": return "道指"
        case "标普500": return "标普"
        default: return shortName(name)
        }
    }
}
