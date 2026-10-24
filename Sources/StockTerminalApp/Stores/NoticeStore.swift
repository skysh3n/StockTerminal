import Foundation
import Observation
import TradingCore

/// 当前选中标的的公告列表（按需拉取）。
@MainActor
@Observable
final class NoticeStore {
    private(set) var items: [StockNotice] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var loadedCode: String?

    private let client = EastmoneyNoticeClient()
    private var usingReal = false
    private var task: Task<Void, Never>?

    func configure(usingRealMarket: Bool) {
        usingReal = usingRealMarket
    }

    func load(for fullCode: String?) {
        task?.cancel()
        guard let fullCode, !fullCode.isEmpty else {
            items = []
            loadedCode = nil
            error = nil
            return
        }
        if loadedCode == fullCode, !items.isEmpty { return }
        loading = true
        error = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.loading = false }
            if !self.usingReal {
                self.items = Self.mockNotices(for: fullCode)
                self.loadedCode = fullCode
                return
            }
            do {
                let list = try await self.client.notices(code: fullCode, limit: 30)
                guard !Task.isCancelled else { return }
                self.items = list
                self.loadedCode = fullCode
                if list.isEmpty { self.error = "暂无公告" }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "公告加载失败"
                self.items = []
            }
        }
    }

    private static func mockNotices(for fullCode: String) -> [StockNotice] {
        let code = String(fullCode.suffix(6))
        return [
            StockNotice(
                artCode: "MOCK1",
                symbol: code,
                title: "（模拟）关于日常经营情况的自愿性信息披露公告",
                noticeDate: "2026-10-20",
                url: nil
            ),
            StockNotice(
                artCode: "MOCK2",
                symbol: code,
                title: "（模拟）董事会决议公告",
                noticeDate: "2026-10-12",
                url: nil
            ),
        ]
    }
}
