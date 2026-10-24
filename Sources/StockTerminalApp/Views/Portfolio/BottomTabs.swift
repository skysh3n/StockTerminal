import SwiftUI
import AppKit
import DesignSystem
import TradingCore

/// 中栏下方：持仓 / 委托 / 成交 / 公告 / 预警
struct BottomTabs: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tab: BottomTab = .positions

    enum BottomTab: String, CaseIterable, Identifiable {
        case positions = "持仓"
        case orders = "委托"
        case trades = "成交"
        case notices = "公告"
        case alerts = "预警"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(BottomTab.allCases) { t in
                    tabButton(t)
                }
                Spacer()
                if tab == .positions || tab == .orders || tab == .trades {
                    summary
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            Rectangle().fill(Color.dsBorder.opacity(0.7)).frame(height: 0.5)

            Group {
                switch tab {
                case .positions: PositionsTable()
                case .orders: OrdersTable()
                case .trades: TradesTable()
                case .notices: NoticesTable()
                case .alerts: AlertsTable()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func tabButton(_ t: BottomTab) -> some View {
        let selected = tab == t
        let count: Int = {
            switch t {
            case .positions: return env.portfolio.positions.count
            case .orders: return env.trading.orders.count
            case .trades: return env.trading.trades.count
            case .notices: return env.notices.items.count
            case .alerts: return env.alerts.alerts.count
            }
        }()
        Button {
            tab = t
            if t == .notices {
                env.notices.load(for: env.watchlist.selectedCode)
            }
        } label: {
            HStack(spacing: 5) {
                Text(t.rawValue)
                    .font(.dsFootnote(medium: selected))
                    .tracking(0.3)
                if count > 0 {
                    Text("\(count)")
                        .font(.dsMicro(medium: true))
                        .foregroundStyle(selected ? Color.dsAccent.opacity(0.9) : Color.dsTextTertiary)
                }
            }
            .foregroundStyle(selected ? Color.dsAccent : Color.dsTextSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Color.dsAccent.opacity(0.10) : Color.clear)
            )
            .overlay(alignment: .bottom) {
                if selected {
                    Rectangle().fill(Color.dsAccent)
                        .frame(height: 1.2)
                        .padding(.horizontal, 8)
                }
            }
            // 文字与数字之间的空隙默认不响应命中，整块标签都要可点。
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private var summary: some View {
        HStack(spacing: 4) {
            Text("浮动盈亏")
                .font(.dsMicro())
                .tracking(0.3)
                .foregroundStyle(Color.dsTextTertiary)
            Text(Fmt.money(totalFloatProfit))
                .font(.dsFootnote(medium: true))
                .foregroundStyle(Sem.change(totalFloatProfitPct))
        }
    }

    private var totalFloatProfit: Decimal {
        env.portfolio.positions.reduce(Decimal.zero) { $0 + $1.profit }
    }

    private var totalFloatProfitPct: Double? {
        let cost = env.portfolio.positions.reduce(Decimal.zero) { $0 + $1.costPrice * Decimal($1.quantity) }
        guard cost > 0 else { return nil }
        return (totalFloatProfit / cost).doubleValue * 100
    }
}

// MARK: - 持仓表

struct PositionsTable: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let positions = env.portfolio.positions
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                headerCell("代码", 66, .leading)
                headerCell("名称", 80, .leading)
                headerCell("持仓", 52, .trailing)
                headerCell("可用", 52, .trailing)
                headerCell("成本价", 64, .trailing)
                headerCell("现价", 64, .trailing)
                headerCell("市值", 78, .trailing)
                headerCell("盈亏", 78, .trailing)
                headerCell("盈亏%", 62, .trailing)
                Spacer(minLength: 8)
                headerCell("操作", 52, .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)

            if positions.isEmpty {
                EmptyHint(text: "暂无持仓 — 在右侧下单面板买入后显示")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(positions) { p in
                            PositionRow(position: p)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

private struct PositionRow: View {
    @Environment(AppEnvironment.self) private var env
    let position: Position

    var body: some View {
        let color = Sem.change(position.profitPercent)
        let sellable = position.availableQuantity > 0
        HStack(spacing: 0) {
            cell(position.symbol, 66, .leading, .dsTextSecondary)
            cell(position.name, 80, .leading, .dsTextPrimary, medium: true)
            cell("\(position.quantity)", 52, .trailing, .dsTextSecondary)
            cell("\(position.availableQuantity)", 52, .trailing, .dsTextSecondary)
            cell(Fmt.price(position.costPrice), 64, .trailing, .dsTextSecondary)
            cell(Fmt.price(position.lastPrice), 64, .trailing, color)
            cell(Fmt.money(position.marketValue), 78, .trailing, .dsTextSecondary)
            cell(Fmt.money(position.profit), 78, .trailing, color, medium: true)
            cell(Fmt.pct(position.profitPercent), 62, .trailing, color, medium: true)
            Spacer(minLength: 8)
            Button {
                env.trading.draft.side = .sell
                env.trading.draft.qtyText = String(position.availableQuantity)
                env.trading.draft.priceText = Fmt.price(position.lastPrice)
            } label: {
                Text("卖出")
                    .font(.dsMicro(medium: true))
                    .tracking(0.3)
                    .foregroundStyle(sellable ? Sem.down : Color.dsTextTertiary)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(sellable ? Sem.down.opacity(0.4) : Color.dsBorder, lineWidth: 0.7)
                    )
            }
            .buttonStyle(PressableStyle())
            .disabled(!sellable)
            .frame(width: 52)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .rowHover(radius: 5)
        .padding(.horizontal, 4)
    }
}

// MARK: - 委托表

struct OrdersTable: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let orders = env.trading.orders
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                headerCell("时间", 66, .leading)
                headerCell("代码", 66, .leading)
                headerCell("名称", 80, .leading)
                headerCell("方向", 36, .center)
                headerCell("类型", 36, .center)
                headerCell("委托价", 62, .trailing)
                headerCell("委托量", 56, .trailing)
                headerCell("成交量", 56, .trailing)
                headerCell("均价", 62, .trailing)
                headerCell("状态", 44, .center)
                Spacer(minLength: 8)
                headerCell("操作", 52, .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)

            if orders.isEmpty {
                EmptyHint(text: "暂无委托 — 下单后在此跟踪状态")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(orders) { o in
                            OrderRow(order: o)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

private struct OrderRow: View {
    @Environment(AppEnvironment.self) private var env
    let order: Order

    var body: some View {
        HStack(spacing: 0) {
            cell(Fmt.orderTime(order.createdAt), 66, .leading, .dsTextTertiary)
            cell(order.symbol, 66, .leading, .dsTextSecondary)
            cell(order.name, 80, .leading, .dsTextPrimary, medium: true)
            cell(order.side.shortLabel, 36, .center, Sem.side(order.side), medium: true)
            cell(order.type.label, 36, .center, .dsTextSecondary)
            cell(order.price.map { Fmt.price($0) } ?? "市价", 62, .trailing, .dsTextSecondary)
            cell("\(order.quantity)", 56, .trailing, .dsTextSecondary)
            cell("\(order.filledQuantity)", 56, .trailing, .dsTextPrimary)
            cell(Fmt.price(order.filledAvgPrice), 62, .trailing, .dsTextSecondary)
            cell(order.status.label, 44, .center, Sem.status(order.status), medium: true)
            Spacer(minLength: 8)
            if order.status.isCancellable {
                Button {
                    Task { await env.trading.cancel(id: order.id) }
                } label: {
                    Text("撤单")
                        .font(.dsMicro(medium: true))
                        .tracking(0.3)
                        .foregroundStyle(Color.dsWarning)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.dsWarning.opacity(0.4), lineWidth: 0.7)
                        )
                }
                .buttonStyle(PressableStyle())
                .frame(width: 52)
            } else {
                Color.clear.frame(width: 52, height: 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .rowHover(radius: 5)
        .padding(.horizontal, 4)
    }
}

// MARK: - 成交表

struct TradesTable: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let trades = env.trading.trades
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                headerCell("时间", 66, .leading)
                headerCell("代码", 66, .leading)
                headerCell("名称", 80, .leading)
                headerCell("方向", 36, .center)
                headerCell("成交价", 64, .trailing)
                headerCell("数量", 56, .trailing)
                headerCell("金额", 82, .trailing)
                headerCell("费用", 56, .trailing)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)

            if trades.isEmpty {
                EmptyHint(text: "暂无成交记录")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(trades) { t in
                            TradeRow(trade: t)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

private struct TradeRow: View {
    let trade: Trade

    var body: some View {
        HStack(spacing: 0) {
            cell(Fmt.orderTime(trade.timestamp), 66, .leading, .dsTextTertiary)
            cell(trade.symbol, 66, .leading, .dsTextSecondary)
            cell(trade.name, 80, .leading, .dsTextPrimary, medium: true)
            cell(trade.side.shortLabel, 36, .center, Sem.side(trade.side), medium: true)
            cell(Fmt.price(trade.price), 64, .trailing, Sem.side(trade.side))
            cell("\(trade.quantity)", 56, .trailing, .dsTextSecondary)
            cell(Fmt.money(trade.amount), 82, .trailing, .dsTextSecondary)
            cell(Fmt.price(trade.fee), 56, .trailing, .dsTextTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .rowHover(radius: 5)
        .padding(.horizontal, 4)
    }
}

// MARK: - 公告

struct NoticesTable: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let store = env.notices
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                headerCell("日期", 78, .leading)
                headerCell("标题", 320, .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)

            if store.loading && store.items.isEmpty {
                EmptyHint(text: "加载公告…")
            } else if store.items.isEmpty {
                EmptyHint(text: store.error ?? "选择股票后查看公告")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(store.items) { n in
                            NoticeRow(notice: n)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

private struct NoticeRow: View {
    let notice: StockNotice

    var body: some View {
        Button {
            if let url = notice.url {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 0) {
                cell(notice.noticeDate, 78, .leading, .dsTextTertiary)
                Text(notice.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(notice.url == nil ? Color.dsTextSecondary : Color.dsTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if notice.url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.dsTextTertiary)
                        .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(notice.url == nil)
        .rowHover(radius: 5)
        .padding(.horizontal, 4)
        .help(notice.url == nil ? notice.title : "在浏览器打开公告")
    }
}

// MARK: - 预警

struct AlertsTable: View {
    @Environment(AppEnvironment.self) private var env
    @State private var draftDirection: PriceAlertDirection = .above
    @State private var draftThreshold = ""

    var body: some View {
        VStack(spacing: 0) {
            alertComposer
            Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)

            HStack(spacing: 0) {
                headerCell("标的", 120, .leading)
                headerCell("条件", 56, .center)
                headerCell("阈值", 72, .trailing)
                headerCell("状态", 56, .center)
                Spacer(minLength: 8)
                headerCell("操作", 88, .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            Rectangle().fill(Color.dsBorder.opacity(0.5)).frame(height: 0.5)

            if env.alerts.alerts.isEmpty {
                EmptyHint(text: "暂无预警 — 在自选行右键或下方为当前标的添加")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(env.alerts.alerts) { a in
                            AlertRow(alert: a)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var alertComposer: some View {
        let code = env.watchlist.selectedCode
        let name = code.flatMap { env.watchlist.symbol(for: $0)?.name } ?? "--"
        let ref = code.flatMap { env.market.states[$0]?.quote?.lastPrice }
        return HStack(spacing: 8) {
            Text(name)
                .font(.dsFootnote(medium: true))
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)
            Picker("", selection: $draftDirection) {
                Text("涨破").tag(PriceAlertDirection.above)
                Text("跌破").tag(PriceAlertDirection.below)
            }
            .labelsHidden()
            .frame(width: 72)
            TextField(ref.map { Fmt.price($0) } ?? "价格", text: $draftThreshold)
                .textFieldStyle(.plain)
                .font(.dsFootnote())
                .foregroundStyle(Color.dsTextPrimary)
                .padding(.horizontal, 8)
                .frame(width: 88, height: 24)
                .inputBox(focused: false)
            Button("添加预警") { commitAlert(code: code, name: name) }
                .buttonStyle(.plain)
                .font(.dsMicro(medium: true))
                .foregroundStyle(Color.dsAccent)
                .disabled(code == nil)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: code) { _, _ in
            if let ref { draftThreshold = Fmt.price(ref) }
        }
        .onAppear {
            if draftThreshold.isEmpty, let ref { draftThreshold = Fmt.price(ref) }
        }
    }

    private func commitAlert(code: String?, name: String) {
        guard let code else { return }
        let cleaned = draftThreshold.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
        guard let threshold = Decimal(string: cleaned), threshold > 0 else {
            env.trading.showToast("请输入有效价格", isError: true)
            return
        }
        if env.alerts.add(symbol: code, name: name, direction: draftDirection, threshold: threshold) {
            env.trading.showToast("已添加预警", isError: false)
        }
    }
}

private struct AlertRow: View {
    @Environment(AppEnvironment.self) private var env
    let alert: PriceAlert

    var body: some View {
        let status: (String, Color) = {
            if let _ = alert.triggeredAt { return ("已触发", Color.dsWarning) }
            if !alert.enabled { return ("关闭", Color.dsTextTertiary) }
            return ("监视中", Color.dsDown)
        }()
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                Text(alert.symbol)
                    .font(.dsMicro())
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .frame(width: 120, alignment: .leading)
            cell(alert.direction.label, 56, .center, .dsTextSecondary, medium: true)
            cell(Fmt.price(alert.threshold), 72, .trailing, .dsTextPrimary)
            cell(status.0, 56, .center, status.1, medium: true)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if alert.triggeredAt != nil {
                    Button("重置") { env.alerts.reset(alert.id) }
                        .buttonStyle(PressableStyle())
                        .font(.dsMicro(medium: true))
                        .foregroundStyle(Color.dsAccent)
                } else {
                    Button(alert.enabled ? "暂停" : "开启") { env.alerts.toggle(alert.id) }
                        .buttonStyle(PressableStyle())
                        .font(.dsMicro(medium: true))
                        .foregroundStyle(Color.dsTextSecondary)
                }
                Button("删除", role: .destructive) { env.alerts.remove(alert.id) }
                    .buttonStyle(PressableStyle())
                    .font(.dsMicro(medium: true))
                    .foregroundStyle(Color.dsUp)
            }
            .frame(width: 88)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .rowHover(radius: 5)
        .padding(.horizontal, 4)
    }
}

// MARK: - 表格通用单元

@ViewBuilder
func headerCell(_ text: String, _ width: CGFloat, _ align: Alignment) -> some View {
    Text(text)
        .font(.dsMicro())
        .tracking(0.3)
        .foregroundStyle(Color.dsTextTertiary)
        .frame(width: width, alignment: align)
}

@ViewBuilder
func cell(_ text: String, _ width: CGFloat, _ align: Alignment, _ color: Color, medium: Bool = false) -> some View {
    Text(text)
        .font(.system(size: 11.5, weight: medium ? .medium : .regular).monospacedDigit())
        .foregroundStyle(color)
        .frame(width: width, alignment: align)
        .lineLimit(1)
}
