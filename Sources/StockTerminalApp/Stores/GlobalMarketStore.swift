import Foundation
import Observation
import TradingCore

/// 全球股指看板：列表快照 + 选中指数的日线。只在界面可见时轮询，隐藏后停止请求。
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

    let indices = GlobalIndex.catalog
    private(set) var quotes: [String: GlobalIndexQuote] = [:]
    private(set) var lastUpdated: Date?
    private(set) var loading = false
    /// 交易状态与当地时间按这个时间计算，随每次轮询刷新。
    private(set) var now = Date()

    var selectedID: String
    var range: Range = .m6
    private(set) var history: [String: [GlobalIndexBar]] = [:]
    private(set) var historyLoading: Set<String> = []
    private var historyFetchedAt: [String: Date] = [:]

    private let client = GlobalIndexClient()
    private var pollTask: Task<Void, Never>?
    private let interval: Duration = .seconds(15)

    init() {
        selectedID = GlobalIndex.catalog.first?.id ?? ""
    }

    var selected: GlobalIndex? { indices.first { $0.id == selectedID } }

    func indices(in region: GlobalIndex.Region) -> [GlobalIndex] {
        indices.filter { $0.region == region }
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
            loadHistoryIfNeeded(selectedID)
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    func select(_ id: String) {
        selectedID = id
        loadHistoryIfNeeded(id)
    }

    func refresh() async {
        loading = true
        let fresh = await client.quotes(for: indices)
        quotes.merge(fresh) { _, new in new }
        now = Date()
        if !fresh.isEmpty { lastUpdated = now }
        loading = false
    }

    /// 日线 10 分钟内不重复拉取。
    private func loadHistoryIfNeeded(_ id: String) {
        guard let index = indices.first(where: { $0.id == id }), index.history != nil,
              !historyLoading.contains(id) else { return }
        if let at = historyFetchedAt[id], Date().timeIntervalSince(at) < 600, history[id]?.isEmpty == false {
            return
        }
        historyLoading.insert(id)
        Task {
            let bars = await client.dailyHistory(for: index, count: 800)
            if !bars.isEmpty {
                history[id] = bars
                historyFetchedAt[id] = Date()
            }
            historyLoading.remove(id)
        }
    }
}
