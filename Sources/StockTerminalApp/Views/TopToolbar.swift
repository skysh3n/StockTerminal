import SwiftUI
import DesignSystem
import TradingCore

/// 顶部工具栏：品牌 + 全市场搜索 + 数据源徽章 + 账户资产摘要
struct TopToolbar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeStore.self) private var theme
    @State private var showSearch = false
    @State private var results: [Symbol] = []
    @State private var previewQuotes: [String: Quote] = [:]
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var wl = env.watchlist
        HStack(spacing: 16) {
            // 红绿灯留白（hiddenTitleBar 窗口）
            Color.clear.frame(width: 58, height: 1)

            logo

            workspaceSwitch

            // 搜索
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(searchFocused ? Color.dsAccent : Color.dsTextTertiary)
                TextField("搜索全市场代码 / 名称", text: $wl.query)
                    .textFieldStyle(.plain)
                    .font(.dsFootnote())
                    .foregroundStyle(Color.dsTextPrimary)
                    .focused($searchFocused)
                    .onSubmit { addFirstResult() }
                    .onChange(of: wl.query) { _, nv in
                        showSearch = !nv.trimmingCharacters(in: .whitespaces).isEmpty
                        runSearch(nv)
                    }
                if !wl.query.isEmpty {
                    Button {
                        wl.query = ""
                        showSearch = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.dsTextTertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("⏎")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.dsTextTertiary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.dsBorderStrong, lineWidth: 0.6))
                }
            }
            .padding(.horizontal, 9)
            .frame(width: 236, height: 28)
            .inputBox(focused: searchFocused)
            .popover(isPresented: $showSearch, arrowEdge: .bottom) {
                searchResults
            }

            Spacer(minLength: 8)

            sourceBadge
            themeToggle
            AccountSummary()
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(
            LinearGradient(
                colors: [Color.dsElevated.opacity(0.55), Color.dsPanel],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder).frame(height: 0.5)
        }
    }

    // MARK: - 品牌区

    private var logo: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [Color.dsAccent, Color.dsAccent.opacity(0.62)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 22, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.28), lineWidth: 0.6)
                    )
                    .shadow(color: Color.dsAccent.opacity(0.25), radius: 6, y: 1)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.dsBgBase)
            }
            Text("量化终端")
                .font(.system(size: 13.5, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.dsTextPrimary)
            Tag(text: "PRO", color: .dsAccent)
        }
    }

    // MARK: - 工作区切换

    private var workspaceSwitch: some View {
        HStack(spacing: 2) {
            workspaceButton(.trading, title: "交易", icon: "chart.bar.xaxis")
                .help("交易终端：自选板块、K 线、五档与下单")
            workspaceButton(.boards, title: "榜单", icon: "list.number")
                .help("市场榜单：涨跌幅、成交额、行业/概念、涨停、龙虎榜")
            workspaceButton(.global, title: "全球", icon: "globe.asia.australia")
                .help("全球市场：主要股指行情与走势（只读）")
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.dsElevated.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.dsBorder, lineWidth: 0.6))
    }

    private func workspaceButton(_ ws: AppEnvironment.Workspace, title: String, icon: String) -> some View {
        let selected = env.workspace == ws
        return Button {
            if ws == .boards {
                env.showBoardsWorkspace()
            } else {
                env.workspace = ws
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.dsFootnote(medium: selected))
            }
            .foregroundStyle(selected ? Color.dsAccent : Color.dsTextSecondary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(selected ? Color.dsAccent.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 主题切换

    private var themeToggle: some View {
        Button {
            theme.cycle()
        } label: {
            Image(systemName: theme.theme.iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dsTextSecondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.dsElevated.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.dsBorder, lineWidth: 0.6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("主题：\(theme.theme.label)（点击切换 深色 / 浅色 / 自动）")
    }

    // MARK: - 数据源徽章

    private var sourceBadge: some View {
        let real = env.usingRealMarket
        let phase = MarketSession.phase()
        let active = phase.isActiveTrading
        let text: String = {
            if !real { return "模拟数据" }
            switch phase {
            case .continuousAM, .continuousPM: return "实时行情"
            case .callAuction: return "实时行情 · 集合竞价"
            case .lunch: return "实时行情 · 午休"
            case .preOpen: return "实时行情 · 开盘前"
            case .afterClose: return "实时行情 · 已收盘"
            case .weekend, .closed: return "实时行情 · 休市"
            }
        }()
        let dotColor: Color = real ? (active ? .dsDown : .dsTextTertiary) : .dsAccent
        return HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
                .shadow(color: dotColor.opacity(active ? 0.6 : 0), radius: 3)
            Text(text)
                .font(.dsMicro(medium: true))
                .tracking(0.3)
                .foregroundStyle(Color.dsTextSecondary)
        }
        .padding(.horizontal, 7).padding(.vertical, 3.5)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.dsElevated.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.dsBorder, lineWidth: 0.6))
        .help(real
              ? "会话：\(phase.label)。数据源：腾讯行情（快照 / K线 / 五档）+ 东方财富（逐笔）；交易为模拟撮合。"
              : "内置模拟行情（真实数据源探测失败或当前离线）")
    }

    // MARK: - 搜索（全市场，防抖 250ms）

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            previewQuotes = [:]
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await env.search(q)
            guard !Task.isCancelled else { return }
            // 批量快照：填价格预览 + 过滤已退市标的（真实行情下拿不到有效报价即不可交易）
            let quotes = await env.previewQuotes(for: found.map(\.fullCode))
            guard !Task.isCancelled else { return }
            previewQuotes = quotes
            var display = found
            if env.usingRealMarket, !quotes.isEmpty {
                display = found.filter { (quotes[$0.fullCode]?.lastPrice ?? 0) > 0 }
            }
            results = Array(display.prefix(10))
            searching = false
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                HStack(spacing: 7) {
                    if searching { ProgressView().controlSize(.mini) }
                    Text(searching ? "搜索中…" : "无匹配结果")
                        .font(.dsFootnote())
                        .foregroundStyle(Color.dsTextTertiary)
                }
                .padding(12)
            } else {
                ForEach(results) { sym in
                    searchRow(sym)
                }
            }
        }
        .frame(width: 272)
        .background(Color.dsPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.dsBorder, lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private func searchRow(_ sym: Symbol) -> some View {
        let q = previewQuotes[sym.fullCode] ?? env.market.states[sym.fullCode]?.quote
        Button {
            selectFromSearch(sym)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(sym.name)
                        .font(.dsBody(medium: true))
                        .foregroundStyle(Color.dsTextPrimary)
                    HStack(spacing: 5) {
                        Text(sym.fullCode)
                            .font(.dsMicro())
                            .foregroundStyle(Color.dsTextTertiary)
                        Tag(text: sym.exchange.rawValue, color: .dsTextTertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1.5) {
                    Text(Fmt.price(q?.lastPrice))
                        .font(.dsBody())
                        .foregroundStyle(Sem.change(q?.changePercent))
                    Text(Fmt.pct(q?.changePercent))
                        .font(.dsMicro())
                        .foregroundStyle(Sem.change(q?.changePercent))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
            .rowHover(radius: 0)
        }
        .buttonStyle(PressableStyle())
    }

    private func selectFromSearch(_ sym: Symbol) {
        env.addToWatchlistAndSelect(sym)
        env.watchlist.query = ""
        showSearch = false
        searchFocused = false
        results = []
        previewQuotes = [:]
    }

    private func addFirstResult() {
        guard let first = results.first else { return }
        selectFromSearch(first)
    }
}

/// 账户资产摘要（工具栏右侧）
struct AccountSummary: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let snap = env.portfolio.snapshot
        HStack(spacing: 0) {
            item("总资产", Fmt.money(snap?.totalAssets), .dsTextPrimary)
            divider
            item("可用资金", Fmt.money(snap?.availableCash), .dsTextPrimary)
            divider
            item("持仓市值", Fmt.money(snap?.marketValue), .dsTextPrimary)
            divider
            VStack(alignment: .leading, spacing: 2) {
                Text("当日盈亏")
                    .font(.dsMicro())
                    .tracking(0.3)
                    .foregroundStyle(Color.dsTextTertiary)
                HStack(spacing: 5) {
                    Text(Fmt.money(snap?.dayProfit))
                    Text(Fmt.pct(snap?.dayProfitPercent))
                }
                .font(.dsFootnote(medium: true))
                .foregroundStyle(Sem.change(snap?.dayProfitPercent))
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.dsBorder)
            .frame(width: 0.5, height: 20)
            .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func item(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dsMicro())
                .tracking(0.3)
                .foregroundStyle(Color.dsTextTertiary)
            Text(value)
                .font(.dsFootnote(medium: true))
                .foregroundStyle(color)
        }
    }
}
