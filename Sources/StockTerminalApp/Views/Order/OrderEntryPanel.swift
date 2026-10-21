import SwiftUI
import DesignSystem
import TradingCore

/// 右下：下单面板（双层容器内：买卖/类型分段 · 价格数量 · 快捷仓位 · 提交按钮带内嵌图标舱）
struct OrderEntryPanel: View {
    @Environment(AppEnvironment.self) private var env
    @FocusState private var priceFocused: Bool
    @FocusState private var qtyFocused: Bool
    /// 收起下单区（由布局层控制）
    var onCollapse: (() -> Void)? = nil

    private struct QuickFraction: Identifiable {
        let frac: Double
        let label: String
        var id: String { label }
    }

    private static let fractions: [QuickFraction] = [
        .init(frac: 0.25, label: "1/4"),
        .init(frac: 0.5, label: "1/2"),
        .init(frac: 0.75, label: "3/4"),
        .init(frac: 1.0, label: "全仓"),
    ]

    var body: some View {
        @Bindable var draft = env.trading.draft
        let code = draft.symbolCode
        let quote = env.market.states[code]?.quote
        let position = env.portfolio.position(for: code)
        let availableCash = env.portfolio.snapshot?.availableCash

        VStack(spacing: 7) {
            PanelHeader("交易下单") {
                HStack(spacing: 6) {
                    Tag(text: "模拟撮合", color: .dsWarning)
                        .help("交易引擎为本地模拟撮合（真实行情驱动），不接入真实券商柜台")
                    if !code.isEmpty {
                        Text(draft.symbolName)
                            .font(.dsMicro())
                            .foregroundStyle(Color.dsTextTertiary)
                            .lineLimit(1)
                    }
                    if let onCollapse {
                        Button(action: onCollapse) {
                            Image(systemName: "rectangle.righthalf.inset.filled")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.dsTextTertiary)
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("收起下单面板")
                    }
                }
            }

            // 买卖方向（分段轨道 + 浮起活动段）
            HStack(spacing: 2) {
                sideButton("买入", side: .buy, color: Sem.up, active: draft.side == .buy) {
                    draft.side = .buy
                }
                sideButton("卖出", side: .sell, color: Sem.down, active: draft.side == .sell) {
                    draft.side = .sell
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.dsInput))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dsBorder, lineWidth: 0.6))

            // 限价 / 市价
            HStack(spacing: 2) {
                typeButton("限价", active: draft.type == .limit) { draft.type = .limit }
                typeButton("市价", active: draft.type == .market) { draft.type = .market }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.dsInput))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.dsBorder.opacity(0.8), lineWidth: 0.6))

            // 价格
            fieldRow(label: "价格") {
                stepField(
                    display: "对手价 \(Fmt.price(draft.side == .buy ? quote?.askPrice1 : quote?.bidPrice1))",
                    fieldPlaceholder: "价格",
                    binding: $draft.priceText,
                    disabled: draft.type == .market,
                    focused: $priceFocused
                ) { delta in
                    let cur = draft.price?.doubleValue ?? refPriceDouble() ?? 0
                    draft.priceText = String(format: "%.2f", max(0.01, cur + Double(delta) * 0.01))
                }
            }

            // 数量
            fieldRow(label: "数量") {
                stepField(
                    display: nil,
                    fieldPlaceholder: "股数",
                    binding: $draft.qtyText,
                    disabled: false,
                    focused: $qtyFocused
                ) { delta in
                    let cur = draft.quantity ?? 0
                    draft.qtyText = String(max(100, cur + delta * 100))
                }
            }

            // 快捷仓位
            HStack(spacing: 5) {
                ForEach(Self.fractions) { item in
                    Button {
                        if let q = percentQty(item.frac, draft: draft, quote: quote,
                                              position: position, cash: availableCash) {
                            draft.qtyText = String(q)
                        }
                    } label: {
                        Text(item.label)
                            .font(.dsMicro(medium: true))
                            .tracking(0.3)
                            .foregroundStyle(Color.dsTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3.5)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(Color.dsElevated.opacity(0.55)))
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.dsBorder, lineWidth: 0.6))
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            // 可用信息
            HStack {
                infoPair(draft.side == .buy ? "可用资金" : "可卖股数",
                         draft.side == .buy
                             ? Fmt.money(availableCash)
                             : "\(position?.availableQuantity ?? 0)")
                Spacer()
                infoPair("预估金额", estimateText(draft: draft, quote: quote))
            }

            // 提交（实色 + 顶部内高光 + 内嵌图标舱）
            Button(action: { submit(draft: draft) }) {
                HStack(spacing: 8) {
                    Text(submitLabel(draft: draft))
                        .font(.system(size: 12.5, weight: .semibold))
                        .tracking(0.3)
                    Spacer()
                    ZStack {
                        Circle().fill(.white.opacity(0.18)).frame(width: 20, height: 20)
                        Image(systemName: draft.side == .buy ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .foregroundStyle(.white.opacity(0.97))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(
                            colors: draft.side == .buy
                                ? [Sem.up.opacity(0.95), Sem.up.opacity(0.78)]
                                : [Sem.down.opacity(0.95), Sem.down.opacity(0.78)],
                            startPoint: .top, endPoint: .bottom
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.white.opacity(0.16), lineWidth: 0.6)
                )
                .shadow(color: (draft.side == .buy ? Sem.up : Sem.down).opacity(0.22),
                        radius: 8, y: 3)
            }
            .buttonStyle(PressableStyle())
            .disabled(code.isEmpty)
            .opacity(code.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .onChange(of: draft.side) { _, newSide in
            guard draft.type == .limit, draft.priceText.isEmpty else { return }
            let q = env.market.states[draft.symbolCode]?.quote
            if let p = newSide == .buy ? q?.askPrice1 : q?.bidPrice1 {
                draft.priceText = String(format: "%.2f", p.doubleValue)
            }
        }
    }

    // MARK: - 分段按钮

    @ViewBuilder
    private func sideButton(_ title: String, side: OrderSide, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dsBody(medium: true))
                .tracking(0.3)
                .foregroundStyle(active ? .white : color.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 29)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active
                              ? LinearGradient(colors: [color, color.opacity(0.82)],
                                               startPoint: .top, endPoint: .bottom)
                              : LinearGradient(colors: [.clear, .clear],
                                               startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(active ? .white.opacity(0.14) : .clear, lineWidth: 0.6)
                )
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private func typeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dsFootnote(medium: active))
                .tracking(0.3)
                .foregroundStyle(active ? Color.dsAccent : Color.dsTextTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5.5)
                        .fill(active ? Color.dsElevated : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5.5)
                        .stroke(active ? Color.dsBorderStrong.opacity(0.8) : .clear, lineWidth: 0.6)
                )
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 输入

    @ViewBuilder
    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.dsMicro())
                .tracking(0.3)
                .foregroundStyle(Color.dsTextTertiary)
                .frame(width: 30, alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private func stepField(
        display: String?,
        fieldPlaceholder: String,
        binding: Binding<String>,
        disabled: Bool,
        focused: FocusState<Bool>.Binding,
        step: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 0) {
            Button { step(-1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(width: 26, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(disabled)

            if disabled {
                Text(display ?? "--")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.dsTextTertiary)
                    .frame(maxWidth: .infinity)
            } else {
                TextField(fieldPlaceholder, text: binding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.dsTextPrimary)
                    .multilineTextAlignment(.center)
                    .focused(focused)
                    .frame(minWidth: 20)
            }

            Button { step(1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(width: 26, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(disabled)
        }
        .inputBox(focused: focused.wrappedValue)
        .frame(height: 30)
    }

    @ViewBuilder
    private func infoPair(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.dsMicro())
                .tracking(0.2)
                .foregroundStyle(Color.dsTextTertiary)
            Text(value)
                .font(.dsMicro(medium: true))
                .foregroundStyle(Color.dsTextSecondary)
        }
    }

    // MARK: - 逻辑

    private func refPriceDouble() -> Double? {
        let q = env.market.states[env.trading.draft.symbolCode]?.quote
        let p = env.trading.draft.side == .buy ? q?.askPrice1 : q?.bidPrice1
        return p?.doubleValue
    }

    private func percentQty(_ frac: Double, draft: OrderDraft, quote: Quote?, position: Position?, cash: Decimal?) -> Int? {
        if draft.side == .buy {
            guard let cash, let p = draft.price ?? quote?.askPrice1, p > 0 else { return nil }
            let maxQty = Int(cash.doubleValue / (p.doubleValue * 1.0005) / 100) * 100
            return max(0, Int(Double(maxQty) * frac) / 100 * 100)
        } else {
            let avail = position?.availableQuantity ?? 0
            if frac >= 1 { return avail }
            return max(0, Int(Double(avail) * frac) / 100 * 100)
        }
    }

    private func estimateText(draft: OrderDraft, quote: Quote?) -> String {
        guard let qty = draft.quantity, qty > 0 else { return "--" }
        let p = draft.type == .market
            ? (draft.side == .buy ? quote?.askPrice1 : quote?.bidPrice1)
            : draft.price
        guard let p else { return "--" }
        return Fmt.money(p * Decimal(qty))
    }

    private func submitLabel(draft: OrderDraft) -> String {
        let qty = draft.quantity ?? 0
        let name = draft.symbolName.isEmpty ? draft.symbolCode : draft.symbolName
        return "\(draft.side.label) \(name)\(qty > 0 ? " · \(qty)股" : "")"
    }

    private func submit(draft: OrderDraft) {
        guard !draft.symbolCode.isEmpty else { return }
        let qty = draft.quantity ?? 0
        let price = draft.type == .limit ? draft.price : nil
        // 数量/价格问题交给引擎统一校验并 toast 报错（对用户也是规则提示）
        let req = OrderRequest(symbol: draft.symbolCode, side: draft.side, type: draft.type,
                               price: price, quantity: qty)
        Task { await env.trading.place(req) }
    }
}
