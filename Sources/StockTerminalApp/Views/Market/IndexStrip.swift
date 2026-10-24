import SwiftUI
import DesignSystem
import TradingCore

/// 交易工作区顶栏下的 A 股主要指数条：点选切图看盘，不改三栏交互。
struct IndexStrip: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(AShareIndices.all.enumerated()), id: \.element.fullCode) { idx, symbol in
                if idx > 0 {
                    Rectangle()
                        .fill(Color.dsBorder.opacity(0.7))
                        .frame(width: 0.5, height: 22)
                }
                indexCell(symbol)
            }
            Spacer(minLength: 8)
            sessionHint
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Color.dsPanel.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder.opacity(0.6)).frame(height: 0.5)
        }
    }

    private func indexCell(_ symbol: Symbol) -> some View {
        let q = env.marketBoard.indexQuotes[symbol.fullCode]
            ?? env.market.states[symbol.fullCode]?.quote
        let selected = env.watchlist.selectedCode == symbol.fullCode
        let color = Sem.change(q?.changePercent)
        return Button {
            env.selectMarketSymbol(symbol)
        } label: {
            HStack(spacing: 8) {
                Text(shortName(symbol.name))
                    .font(.dsMicro(medium: true))
                    .foregroundStyle(selected ? Color.dsAccent : Color.dsTextSecondary)
                Text(Fmt.price(q?.lastPrice))
                    .font(.dsFootnote(medium: true))
                    .foregroundStyle(color)
                Text(Fmt.pct(q?.changePercent))
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
        .buttonStyle(PressableStyle())
        .help("\(symbol.name) \(symbol.fullCode) — 点击看盘")
    }

    private var sessionHint: some View {
        let open = MarketSession.isOpen()
        return Text(open ? "交易中" : "已休市")
            .font(.dsMicro())
            .tracking(0.3)
            .foregroundStyle(open ? Color.dsDown : Color.dsTextTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.dsElevated.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.dsBorder, lineWidth: 0.5))
    }

    private func shortName(_ name: String) -> String {
        if name.hasSuffix("指数") { return String(name.dropLast(2)) }
        if name.hasSuffix("指") { return String(name.dropLast(1)) }
        return name
    }
}
