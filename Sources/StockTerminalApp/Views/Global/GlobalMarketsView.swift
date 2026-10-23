import SwiftUI
import DesignSystem
import TradingCore

/// 「全球市场」工作区：左侧指数列表，右侧只读详情。没有五档、逐笔与下单。
struct GlobalMarketsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: 0) {
            GlobalMarketsList()
                .terminalCard()
                .padding(.leading, 8)
                .padding(.vertical, 8)
                .frame(width: 340)

            GlobalIndexDetail()
                .terminalCard()
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { env.globalMarkets.setVisible(true) }
        .onDisappear { env.globalMarkets.setVisible(false) }
    }
}
