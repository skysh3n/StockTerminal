import Foundation
import Observation
import TradingCore

/// 全球股指看板：总览卡片 + 点选详情。详情图表复用个股的 KLineSeries / 分时 / 蜡烛组件。
@MainActor
@Observable
final class GlobalMarketStore {
    enum ChartTab: String, CaseIterable, Identifiable {
        case timeShare = "分时"
        case day = "日K"
        case week = "周K"
        case month = "月K"
        var id: String { rawValue }

        var timeFrame: TimeFrame {
            switch self {
            case .timeShare: return .timeShare
            case .day: return .day
            case .week, .month: return .week
            }
        }
    }

    /// 卡片迷你曲线用最近约 1 个月交易日。
    static let sparkDays = 22

    let indices = GlobalIndex.catalog
    private(set) var quotes: [String: GlobalIndexQuote] = [:]
    private(set) var lastUpdated: Date?
    private(set) var loading = false
    private(set) var now = Date()

    /// `nil` = 总览；有值 = 详情。
    var selectedID: String?
    var chartTab: ChartTab = .timeShare

    /// 与个股图表相同的序列容器，详情页直接喂给 TimeShare / Candle 组件。
    private(set) var activeSeries: KLineSeries?

    private(set) var dayHistory: [String: [GlobalIndexBar]] = [:]
    private(set) var weekHistory: [String: [GlobalIndexBar]] = [:]
    private(set) var monthHistory: [String: [GlobalIndexBar]] = [:]
    private(set) var minuteSeries: [String: GlobalMinuteSeries] = [:]
    private(set) var historyLoading: Set<String> = []

    private var dayFetchedAt: [String: Date] = [:]
    private var weekFetchedAt: [String: Date] = [:]
    private var monthFetchedAt: [String: Date] = [:]
    private var minuteFetchedAt: [String: Date] = [:]

    private let client = GlobalIndexClient()
    private var pollTask: Task<Void, Never>?
    private var minuteTick = 0

    var selected: GlobalIndex? {
        guard let selectedID else { return nil }
        return indices.first { $0.id == selectedID }
    }

    var anyTrading: Bool {
        indices.contains { $0.isTrading(at: now) }
    }

    func indices(in region: GlobalIndex.Region) -> [GlobalIndex] {
        indices.filter { $0.region == region }
    }

    func sparkBars(for id: String) -> [GlobalIndexBar] {
        Array((dayHistory[id] ?? []).suffix(Self.sparkDays))
    }

    func chartBars(for id: String) -> [GlobalIndexBar] {
        switch chartTab {
        case .timeShare: return minuteSeries[id]?.bars ?? []
        case .day: return dayHistory[id] ?? []
        case .week: return weekHistory[id] ?? []
        case .month: return monthHistory[id] ?? []
        }
    }

    func minutePreClose(for id: String) -> Double? {
        minuteSeries[id]?.preClose ?? quotes[id]?.preClose
    }

    func setVisible(_ visible: Bool) {
        if visible {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    let seconds = self?.pollIntervalSeconds ?? 15
                    try? await Task.sleep(for: .seconds(seconds))
                }
            }
            prefetchSparklines()
            if let selectedID { loadDetailData(selectedID) }
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private var pollIntervalSeconds: Int {
        anyTrading ? 3 : 20
    }

    func select(_ id: String) {
        selectedID = id
        chartTab = .timeShare
        activeSeries = nil
        loadDetailData(id)
    }

    func clearSelection() {
        selectedID = nil
        activeSeries = nil
    }

    func setChartTab(_ tab: ChartTab) {
        guard chartTab != tab else { return }
        chartTab = tab
        activeSeries = nil
        guard let id = selectedID else { return }
        loadDetailData(id)
    }

    func refresh() async {
        loading = true
        let fresh = await client.quotes(for: indices)
        quotes.merge(fresh) { _, new in new }
        now = Date()
        if !fresh.isEmpty { lastUpdated = now }
        loading = false

        minuteTick += 1
        if let id = selectedID, chartTab == .timeShare,
           let index = selected, index.isTrading(at: now),
           minuteTick % 5 == 0 {
            await reloadMinute(id)
            rebuildActiveSeries()
        }
    }

    private func prefetchSparklines() {
        for index in indices where index.history != nil {
            loadDayIfNeeded(index.id, count: 40)
        }
    }

    private func loadDetailData(_ id: String) {
        guard let index = indices.first(where: { $0.id == id }) else { return }
        switch chartTab {
        case .timeShare:
            loadMinuteIfNeeded(id)
            if index.history != nil { loadDayIfNeeded(id, count: 800) }
        case .day:
            loadDayIfNeeded(id, count: 800)
        case .week:
            loadWeekIfNeeded(id)
        case .month:
            loadMonthIfNeeded(id)
        }
        rebuildActiveSeries()
    }

    private func rebuildActiveSeries() {
        guard let id = selectedID else {
            activeSeries = nil
            return
        }
        let bars = chartBars(for: id).map(\.asKLine)
        let pre: Decimal? = {
            if chartTab == .timeShare, let p = minutePreClose(for: id) { return Decimal(p) }
            if let p = quotes[id]?.preClose { return Decimal(p) }
            return nil
        }()
        let series = KLineSeries(symbol: id, timeFrame: chartTab.timeFrame)
        series.load(bars, preClose: pre)
        activeSeries = series
    }

    private func loadDayIfNeeded(_ id: String, count: Int) {
        guard let index = indices.first(where: { $0.id == id }), index.history != nil,
              !historyLoading.contains("day:\(id)") else { return }
        let existing = dayHistory[id]?.count ?? 0
        if let at = dayFetchedAt[id], Date().timeIntervalSince(at) < 600, existing >= min(count, Self.sparkDays),
           count <= existing {
            if chartTab == .day { rebuildActiveSeries() }
            return
        }
        historyLoading.insert("day:\(id)")
        Task {
            let bars = await client.klineHistory(for: index, period: .day, count: count)
            if !bars.isEmpty, bars.count >= (dayHistory[id]?.count ?? 0) {
                dayHistory[id] = bars
                dayFetchedAt[id] = Date()
            }
            historyLoading.remove("day:\(id)")
            if selectedID == id, chartTab == .day || chartTab == .timeShare {
                rebuildActiveSeries()
            }
        }
    }

    private func loadWeekIfNeeded(_ id: String) {
        guard let index = indices.first(where: { $0.id == id }), index.history != nil,
              !historyLoading.contains("week:\(id)") else { return }
        if let at = weekFetchedAt[id], Date().timeIntervalSince(at) < 600, !(weekHistory[id] ?? []).isEmpty {
            rebuildActiveSeries()
            return
        }
        historyLoading.insert("week:\(id)")
        Task {
            let bars = await client.klineHistory(for: index, period: .week, count: 200)
            if !bars.isEmpty {
                weekHistory[id] = bars
                weekFetchedAt[id] = Date()
            }
            historyLoading.remove("week:\(id)")
            if selectedID == id, chartTab == .week { rebuildActiveSeries() }
        }
    }

    private func loadMonthIfNeeded(_ id: String) {
        guard let index = indices.first(where: { $0.id == id }), index.history != nil,
              !historyLoading.contains("month:\(id)") else { return }
        if let at = monthFetchedAt[id], Date().timeIntervalSince(at) < 600, !(monthHistory[id] ?? []).isEmpty {
            rebuildActiveSeries()
            return
        }
        historyLoading.insert("month:\(id)")
        Task {
            let bars = await client.klineHistory(for: index, period: .month, count: 120)
            if !bars.isEmpty {
                monthHistory[id] = bars
                monthFetchedAt[id] = Date()
            }
            historyLoading.remove("month:\(id)")
            if selectedID == id, chartTab == .month { rebuildActiveSeries() }
        }
    }

    private func loadMinuteIfNeeded(_ id: String) {
        guard let index = indices.first(where: { $0.id == id }),
              index.tencentMinuteCode != nil,
              !historyLoading.contains("min:\(id)") else {
            if chartTab == .timeShare { rebuildActiveSeries() }
            return
        }
        let trading = index.isTrading(at: now)
        let ttl: TimeInterval = trading ? 20 : 300
        if let at = minuteFetchedAt[id], Date().timeIntervalSince(at) < ttl,
           !(minuteSeries[id]?.bars.isEmpty ?? true) {
            rebuildActiveSeries()
            return
        }
        historyLoading.insert("min:\(id)")
        Task {
            await reloadMinute(id)
            historyLoading.remove("min:\(id)")
            if selectedID == id, chartTab == .timeShare { rebuildActiveSeries() }
        }
    }

    private func reloadMinute(_ id: String) async {
        guard let index = indices.first(where: { $0.id == id }) else { return }
        let series = await client.minuteHistory(for: index)
        if !series.bars.isEmpty {
            minuteSeries[id] = series
            minuteFetchedAt[id] = Date()
        }
    }
}
