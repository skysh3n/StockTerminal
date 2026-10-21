import SwiftUI
import DesignSystem
import TradingCore

/// 右上：五档盘口（卖5→卖1 / 最新价 / 买1→买5，深度条随挂单量伸缩）
struct OrderBookPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let code = env.watchlist.selectedCode
        let state = code.flatMap { env.market.states[$0] }

        VStack(spacing: 0) {
            PanelHeader("五档盘口") {
                if let spread = state?.book?.spread, spread > 0 {
                    Text("价差 " + Fmt.price(spread))
                        .font(.dsMicro())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }
            Rectangle().fill(Color.dsBorder.opacity(0.7)).frame(height: 0.5)
            if let book = state?.book, let preClose = state?.preClose {
                OrderBookRows(book: book, preClose: preClose, lastPrice: state?.quote?.lastPrice)
            } else {
                EmptyHint(text: "等待盘口数据…")
                    .frame(minHeight: 160)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct OrderBookRows: View {
    let book: OrderBook
    let preClose: Decimal
    /// 快照里的成交价。休市时买一卖一中间价会和收盘价对不上，必须用这个。
    let lastPrice: Decimal?

    private var maxVol: Int {
        max(book.asks.map(\.volume).max() ?? 1, book.bids.map(\.volume).max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            VStack(spacing: 1.5) {
                // 卖五 → 卖一（价格自上而下递减）
                ForEach((0..<min(5, book.asks.count)).reversed(), id: \.self) { i in
                    BookRow(label: "卖\(i + 1)", level: book.asks[i], preClose: preClose,
                            ratio: Double(book.asks[i].volume) / Double(maxVol),
                            tint: Sem.down, width: width)
                }

                midStrip

                ForEach(0..<min(5, book.bids.count), id: \.self) { i in
                    BookRow(label: "买\(i + 1)", level: book.bids[i], preClose: preClose,
                            ratio: Double(book.bids[i].volume) / Double(maxVol),
                            tint: Sem.up, width: width)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    private var midStrip: some View {
        let last = lastPrice ?? book.bestBid?.price ?? preClose
        let color = Sem.price(last, ref: preClose)
        return HStack(spacing: 7) {
            Rectangle().fill(Color.dsBorder.opacity(0.8)).frame(height: 0.5)
            Text("最新")
                .font(.dsMicro())
                .tracking(0.3)
                .foregroundStyle(Color.dsTextTertiary)
            Text(Fmt.price(last))
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
            Rectangle().fill(Color.dsBorder.opacity(0.8)).frame(height: 0.5)
        }
        .padding(.vertical, 3)
    }
}

private struct BookRow: View {
    let label: String
    let level: OrderBook.Level
    let preClose: Decimal
    let ratio: Double
    let tint: Color
    let width: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.dsMicro())
                .foregroundStyle(Color.dsTextTertiary)
                .frame(width: 24, alignment: .leading)
            Text(Fmt.price(level.price))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Sem.price(level.price, ref: preClose))
                .frame(width: 62, alignment: .trailing)
            Spacer(minLength: 4)
            Text("\(level.volume / 100)")
                .font(.dsFootnote())
                .foregroundStyle(Color.dsTextSecondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 3)
                .fill(tint.opacity(0.13))
                .frame(width: max(width * ratio * 0.88, 2))
        }
    }
}
