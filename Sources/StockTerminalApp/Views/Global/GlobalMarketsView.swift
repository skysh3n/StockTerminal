import SwiftUI
import DesignSystem
import TradingCore

/// 「全球市场」工作区：卡片总览一眼扫全市场，点某张进入只读详情。无五档 / 逐笔 / 下单。
struct GlobalMarketsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.globalMarkets.selectedID != nil {
                GlobalIndexDetail()
                    .terminalCard()
                    .padding(8)
            } else {
                GlobalMarketsOverview()
                    .terminalCard()
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: env.globalMarkets.selectedID)
        .onAppear { env.globalMarkets.setVisible(true) }
        .onDisappear { env.globalMarkets.setVisible(false) }
    }
}
