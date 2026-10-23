import Foundation
import Observation
import TradingCore

/// 全球股指看板：总览卡片 + 点选详情。交易中加速轮询；详情支持分时 / 日K / 周K / 月K。
@MainActor
@Observable
final class GlobalMarketStore {
    enum ChartTab: String, CaseIterable, Identifiable {
        case timeShare = "分时"
        case day = "日K"
        case week = "周K"
        case month = "月K"
        var id: String { rawValue }
    }

    enum DayRange: String, CaseIterable, Identifiable {
        case m1 = "1月", m3 = "3月", m6 = "6月", y1 = "1年", y3 = "3年", all = "全部"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .m1: return 22
            case .m3: return 66
            case .m6: return 130
            case .y1: return 250
            case .y3: return 750
            case .all: return nil
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
    var dayRange: DayRange = .m6

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

    /// 详情当前图表数据。
    func chartBars(for id: String) -> [GlobalIndexBar] {
        switch chartTab {
        case .timeShare:
            return minuteSeries[id]?.bars ?? []
        case .day:
            let all = dayHistory[id] ?? []
            if let days = dayRange.days { return Array(all.suffix(days)) }
            return all
        case .week:
            return weekHistory[id] ?? []
        case .month:
            return monthHistory[id] ?? []
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

    /// 有市场交易中时 3 秒刷新报价；全休市 20 秒。
    private var pollIntervalSeconds: Int {
        anyTrading ? 3 : 20
    }

    func select(_ id: String) {
        selectedID = id
        chartTab = .timeShare
        loadDetailData(id)
    }

    func clearSelection() {
        selectedID = nil
    }

    func setChartTab(_ tab: ChartTab) {
        chartTab = tab
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

        // 详情在交易中看分时时，约每 15 秒（5 个快拍）重拉一次分时。
        minuteTick += 1
        if let id = selectedID, chartTab == .timeShare,
           let index = selected, index.isTrading(at: now),
           minuteTick % 5 == 0 {
            await reloadMinute(id)
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
            // 分时页也预拉日线，供统计区 52 周高低。
            if index.history != nil { loadDayIfNeeded(id, count: 800) }
        case .day:
            loadDayIfNeeded(id, count: 800)
        case .week:
            loadWeekIfNeeded(id)
        case .month:
            loadMonthIfNeeded(id)
        }
    }

    private func loadDayIfNeeded(_ id: String, count: Int) {
        guard let index = indices.first(where: { $0.id == id }), index.history != nil,
              !historyLoading.contains("day:\(id)") else { return }
        let existing = dayHistory[id]?.count ?? 0
        if let at = dayFetchedAt[id], Date().timeIntervalSince(at) < 600, existing >= min(count, Self.sparkDays),
           count <= existing { return }
        historyLoading.insert("day:\(id)")
        Task {
            let bars = await client.klineHistory(for: index, period: .day, count: count)
            if !bars.isEmpty, bars.count >= (dayHistory[id]?.count ?? 0) {
                dayHistory[id] = bars
                dayFetchedAt[id] = Date()
            }
            historyLoading.remove("day:\(id)")
        }
    }

    private func loadWeekIfNeeded(_ id: String) {
        guard let index = indices.first(where: { $0.id == id }), index.history != nil,
              !historyLoading.contains("week:\(id)") else { return }
        if let at = weekFetchedAt[id], Date().timeIntervalSince(at) < 600, !(weekHistory[id] ?? []).isEmpty { return }
        historyLoading.insert("week:\(id)")
        Task {
            let bars = await client.klineHistory(for: index, period: .week, count: 200)
            if !bars.isEmpty {
                weekHistory[id] = bars
                weekFetchedAt[id] = Date()
            }
            historyLoading.remove("week:\(id)")
        }
    }

    private func loadMonthIfNeeded(_ id: String) {
        guard let index = indices.first(where: { $0.id == id }), index.history != nil,
              !historyLoading.contains("month:\(id)") else { return }
        if let at = monthFetchedAt[id], Date().timeIntervalSince(at) < 600, !(monthHistory[id] ?? []).isEmpty { return }
        historyLoading.insert("month:\(id)")
        Task {
            let bars = await client.klineHistory(for: index, period: .month, count: 120)
            if !bars.isEmpty {
                monthHistory[id] = bars
                monthFetchedAt[id] = Date()
            }
            historyLoading.remove("month:\(id)")
        }
    }

    private func loadMinuteIfNeeded(_ id: String) {
        guard let index = indices.first(where: { $0.id == id }),
              index.tencentMinuteCode != nil,
              !historyLoading.contains("min:\(id)") else { return }
        let trading = index.isTrading(at: now)
        let ttl: TimeInterval = trading ? 20 : 300
        if let at = minuteFetchedAt[id], Date().timeIntervalSince(at) < ttl,
           !(minuteSeries[id]?.bars.isEmpty ?? true) { return }
        historyLoading.insert("min:\(id)")
        Task {
            await reloadMinute(id)
            historyLoading.remove("min:\(id)")
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
