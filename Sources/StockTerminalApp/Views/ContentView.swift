import SwiftUI
import DesignSystem
import TradingCore

/// 主布局：顶部工具栏 + 三栏可拖拽分栏。
/// 视觉语言：窗口底为深炭黑，面板为悬浮卡片（圆角 + 发丝描边 + 顶部内高光），
/// 卡片间沟槽露出底色；栏宽/栏高与下单区收起状态都写入 UserDefaults。
struct ContentView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var layout = LayoutStore()

    var body: some View {
        Group {
            if env.isReady {
                terminal
            } else {
                bootScreen
            }
        }
        .task { await env.bootstrap() }
        .windowFrameAutosave("StockTerminal.MainWindow")
    }

    private var bootScreen: some View {
        ZStack {
            Color.dsBgBase
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("正在连接行情")
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
            }
        }
    }

    private var terminal: some View {
        VStack(spacing: 0) {
            TopToolbar()
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)

            switch env.workspace {
            case .trading: tradingWorkspace
            case .boards: BoardsWorkspaceView()
            case .global: GlobalMarketsView()
            }
        }
        .background(ambientBackground)
        .overlay(alignment: .top) { toastView }
        .animation(.spring(duration: 0.35), value: env.trading.toast)
        .onChange(of: env.watchlist.selectedCode) { _, _ in env.selectionChanged() }
        .onChange(of: env.watchlist.selectedTimeFrame) { _, _ in env.selectionChanged() }
    }

    private var tradingWorkspace: some View {
        VStack(spacing: 0) {
            IndexStrip()
            GeometryReader { geo in
                // 中间栏吃剩余宽度，避免 left+mid+right 算出来超过总宽导致 HStack 互相挤压抖动。
                let gap: CGFloat = 5
                let midMin: CGFloat = 420
                let usable = max(geo.size.width - gap * 2, midMin + 200 + 260)
                let leftMax = min(420, max(200, usable - midMin - layout.rightWidth))
                let rightMax = min(440, max(260, usable - midMin - layout.leftWidth))
                let left = LayoutStore.clamp(layout.leftWidth, 200...leftMax)
                let right = LayoutStore.clamp(layout.rightWidth, 260...rightMax)

                HStack(spacing: 0) {
                    Group {
                        switch env.workspace {
                        case .boards: MarketBoardsPanel()
                        default: WatchlistPanel()
                        }
                    }
                        .terminalCard()
                        .padding(.leading, 8)
                        .padding(.vertical, 8)
                        .frame(width: left)
                        .clipped()

                    WidthDragDivider(
                        width: $layout.leftWidth,
                        sign: 1,
                        range: 200...leftMax,
                        onSave: { layout.scheduleSave() }
                    )

                    centerColumn
                        .frame(maxWidth: .infinity)
                        .clipped()

                    WidthDragDivider(
                        width: $layout.rightWidth,
                        sign: -1,
                        range: 260...rightMax,
                        onSave: { layout.scheduleSave() }
                    )

                    rightColumn
                        .frame(width: right)
                        .clipped()
                }
            }
        }
        .onChange(of: env.alerts.pendingToast) { _, new in
            if new != nil { env.drainAlertToast() }
        }
    }

    private var centerColumn: some View {
        GeometryReader { geo in
            let total = geo.size.height
            let chartH = total * layout.chartFraction

            VStack(spacing: 0) {
                ChartPanel()
                    .terminalCard()
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .frame(height: max(180, chartH - 2.5))
                    .clipped()

                FractionDragDivider(
                    fraction: $layout.chartFraction,
                    totalHeight: total,
                    range: 0.35...0.85,
                    onSave: { layout.scheduleSave() }
                )

                BottomTabs()
                    .terminalCard()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
        }
    }

    private var rightColumn: some View {
        // 五档 + 逐笔占满右栏；下单展开时浮在逐笔之上，不把逐笔挤矮。
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                let stackH = geo.size.height
                let bookH = stackH * layout.bookFraction

                VStack(spacing: 0) {
                    OrderBookPanel()
                        .terminalCard()
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .frame(height: max(160, bookH - 2.5))
                        .clipped()

                    FractionDragDivider(
                        fraction: $layout.bookFraction,
                        totalHeight: stackH,
                        range: 0.30...0.80,
                        onSave: { layout.scheduleSave() }
                    )

                    TickListPanel()
                        .terminalCard()
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .frame(maxHeight: .infinity)
                        .clipped()
                }
            }

            if layout.orderEntryCollapsed {
                collapsedOrderBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                OrderEntryPanel(onCollapse: { layout.toggleOrderEntry() })
                    .bezel()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: Color.dsShadow.opacity(0.45), radius: 18, y: -4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// 收起后的交易下单条：点按或侧栏图标展开。
    private var collapsedOrderBar: some View {
        Button(action: { layout.toggleOrderEntry() }) {
            HStack(spacing: 8) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 1, bottomLeadingRadius: 1,
                    bottomTrailingRadius: 1, topTrailingRadius: 1
                )
                .fill(Color.dsAccent.opacity(0.85))
                .frame(width: 2, height: 9)
                Text("交易下单")
                    .font(.dsLabel(medium: true))
                    .tracking(0.5)
                    .foregroundStyle(Color.dsTextSecondary)
                Spacer(minLength: 0)
                Image(systemName: "rectangle.righthalf.inset.filled")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTextTertiary)
                    .help("展开下单面板")
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .terminalCard(radius: 8)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var ambientBackground: some View {
        ZStack {
            Color.dsBgBase
            RadialGradient(
                colors: [Color.dsSheen.opacity(ThemePaletteCache.isDark ? 0.035 : 0.06), .clear],
                center: .top, startRadius: 0, endRadius: 640
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var toastView: some View {
        if let t = env.trading.toast {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill((t.isError ? Color.dsUp : Color.dsAccent).opacity(0.14))
                        .frame(width: 26, height: 26)
                    Image(systemName: t.isError ? "exclamationmark" : "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(t.isError ? Color.dsUp : Color.dsAccent)
                }
                Text(t.text)
                    .font(.dsBody(medium: true))
                    .foregroundStyle(Color.dsTextPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.dsElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.dsBorderStrong.opacity(0.7), lineWidth: 0.8)
            )
            .shadow(color: Color.dsShadow.opacity(0.55), radius: 24, y: 10)
            .padding(.top, 62)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
