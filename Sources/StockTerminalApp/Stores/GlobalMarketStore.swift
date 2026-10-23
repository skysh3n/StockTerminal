import Foundation
import Observation
import TradingCore

/// 全球股指看板。只在界面可见时轮询，隐藏后停止请求。
@MainActor
@Observable
final class GlobalMarketStore {
    let indices = GlobalIndex.catalog
    private(set) var quotes: [String: GlobalIndexQuote] = [:]
    private(set) var lastUpdated: Date?
    private(set) var loading = false
    /// 交易状态按这个时间计算，随每次轮询刷新。
    private(set) var now = Date()

    private let client = GlobalIndexClient()
    private var pollTask: Task<Void, Never>?
    private let interval: Duration = .seconds(15)

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
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    func refresh() async {
        loading = true
        let fresh = await client.quotes(for: indices)
        quotes.merge(fresh) { _, new in new }
        now = Date()
        if !fresh.isEmpty { lastUpdated = now }
        loading = false
    }
}
