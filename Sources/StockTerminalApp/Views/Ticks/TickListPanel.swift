import SwiftUI
import DesignSystem
import TradingCore

/// 右中：逐笔成交流（外盘红 / 内盘绿，新→旧，上限 200 条）
struct TickListPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let code = env.watchlist.selectedCode
        let state = code.flatMap { env.market.states[$0] }

        VStack(spacing: 0) {
            PanelHeader("逐笔成交") {
                if let n = state?.ticks.count, n > 0 {
                    Tag(text: "\(n) 笔", color: .dsTextSecondary)
                }
            }
            Rectangle().fill(Color.dsBorder.opacity(0.7)).frame(height: 0.5)

            // 列头
            HStack(spacing: 4) {
                Text("时间").tracking(0.3).frame(width: 52, alignment: .leading)
                Text("价格").tracking(0.3).frame(maxWidth: .infinity, alignment: .trailing)
                Text("手数").tracking(0.3).frame(width: 44, alignment: .trailing)
                Text("性质").tracking(0.3).frame(width: 34, alignment: .trailing)
            }
            .font(.dsMicro())
            .foregroundStyle(Color.dsTextTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)

            if let ticks = state?.ticks, !ticks.isEmpty {
                let preClose = state?.preClose
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // 只渲染最近 60 条：LazyVStack 的 diff 成本与数据量成正比
                        ForEach(ticks.prefix(60)) { t in
                            TickRow(tick: t, preClose: preClose)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                let realClosed = env.usingRealMarket && !MarketSession.isOpen()
                EmptyHint(text: realClosed ? "休市 · 暂无逐笔数据" : "等待成交数据…")
            }
        }
    }
}

private struct TickRow: View {
    let tick: Tick
    let preClose: Decimal?

    var body: some View {
        HStack(spacing: 4) {
            Text(Fmt.clock(tick.timestamp))
                .font(.dsMicro())
                .foregroundStyle(Color.dsTextTertiary)
                .frame(width: 52, alignment: .leading)
            Text(Fmt.price(tick.price))
                .font(.dsFootnote(medium: true))
                .foregroundStyle(Sem.price(tick.price, ref: preClose))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(tick.volume / 100)")
                .font(.dsFootnote())
                .foregroundStyle(Color.dsTextSecondary)
                .frame(width: 44, alignment: .trailing)
            Text(tick.direction == .neutral ? "—" : tick.direction.label)
                .font(.dsMicro(medium: true))
                .tracking(0.2)
                .foregroundStyle(Sem.direction(tick.direction))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .padding(.horizontal, 4)
    }
}
