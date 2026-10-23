import Foundation
import Observation
import TradingCore

/// 全球股指看板：总览卡片 + 点选详情。只在界面可见时轮询，隐藏后停止请求。
@MainActor
@Observable
final class GlobalMarketStore {
    enum Range: String, CaseIterable, Identifiable {
        case m1 = "1月", m3 = "3月", m6 = "6月", y1 = "1年", y3 = "3年"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .m1: return 22
            case .m3: return 66
            case .m6: return 130
            case .y1: return 250
            case .y3: return 750
            }
        }
    }

    /// 卡片迷你曲线用最近约 1 个月交易日。
    static let sparkDays = 22

    let indices = GlobalIndex.catalog
    private(set) var quotes: [String: GlobalIndexQuote] = [:]
    private(set) var lastUpdated: Date?
    private(set) var loading = false
    /// 交易状态与当地时间按这个时间计算，随每次轮询刷新。
    private(set) var now = Date()

    /// `nil` = 总览卡片网格；有值 = 详情页。
    var selectedID: String?
    var range: Range = .m6
    private(set) var history: [String: [GlobalIndexBar]] = [:]
    private(set) var historyLoading: Set<String> = []
    private var historyFetchedAt: [String: Date] = [:]

    private let client = GlobalIndexClient()
    private var pollTask: Task<Void, Never>?
    private let interval: Duration = .seconds(15)

    var selected: GlobalIndex? {
        guard let selectedID else { return nil }
        return indices.first { $0.id == selectedID }
    }

    func indices(in region: GlobalIndex.Region) -> [GlobalIndex] {
        indices.filter { $0.region == region }
    }

    /// 卡片迷你曲线：最近 `sparkDays` 根收盘价。
    func sparkBars(for id: String) -> [GlobalIndexBar] {
        Array((history[id] ?? []).suffix(Self.sparkDays))
    }

    func setVisible(_ visible: Bool) {
        if visible {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    try? await Task.sleep(for: self?.interval ?? .seconds(15))
                }
            }
            prefetchSparklines()
            if let selectedID { loadHistoryIfNeeded(selectedID, count: 800) }
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    func select(_ id: String) {
        selectedID = id
        loadHistoryIfNeeded(id, count: 800)
    }

    func clearSelection() {
        selectedID = nil
    }

    func refresh() async {
        loading = true
        let fresh = await client.quotes(for: indices)
        quotes.merge(fresh) { _, new in new }
        now = Date()
        if !fresh.isEmpty { lastUpdated = now }
        loading = false
    }

    /// 总览卡片：有历史源的指数各拉约 40 根日线（够画 1 个月迷你曲线）。
    private func prefetchSparklines() {
        for index in indices where index.history != nil {
            loadHistoryIfNeeded(index.id, count: 40)
        }
    }

    /// 日线 10 分钟内不重复拉取；已有足够根数则跳过。
    private func loadHistoryIfNeeded(_ id: String, count: Int) {
        guard let index = indices.first(where: { $0.id == id }), index.history != nil,
              !historyLoading.contains(id) else { return }
        let existing = history[id]?.count ?? 0
        if let at = historyFetchedAt[id], Date().timeIntervalSince(at) < 600, existing >= min(count, Self.sparkDays) {
            if count <= existing { return }
        }
        historyLoading.insert(id)
        Task {
            let bars = await client.dailyHistory(for: index, count: count)
            if !bars.isEmpty {
                // 详情需要更长历史时，保留较长的那份。
                if bars.count >= (history[id]?.count ?? 0) {
                    history[id] = bars
                }
                historyFetchedAt[id] = Date()
            }
            historyLoading.remove(id)
        }
    }
}
