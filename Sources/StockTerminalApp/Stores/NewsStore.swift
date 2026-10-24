import Foundation
import Observation
import TradingCore

/// 市场资讯标题流（下栏「资讯」Tab）。
@MainActor
@Observable
final class NewsStore {
    private(set) var items: [NewsHeadline] = []
    private(set) var loading = false
    private(set) var error: String?

    private let client = EastmoneyNewsClient()
    private var usingReal = false

    func configure(usingRealMarket: Bool) {
        usingReal = usingRealMarket
    }

    func refresh() async {
        loading = true
        error = nil
        defer { loading = false }
        if usingReal {
            do {
                items = try await client.headlines(limit: 40)
                if items.isEmpty { error = "暂无资讯" }
            } catch {
                self.error = "资讯加载失败"
                if items.isEmpty { items = Self.mockItems() }
            }
        } else {
            items = Self.mockItems()
        }
    }

    private static func mockItems() -> [NewsHeadline] {
        [
            NewsHeadline(
                code: "MOCKN1",
                title: "（模拟）市场情绪回暖，结构性机会仍存",
                mediaName: "模拟资讯",
                showTime: "2026-10-24 09:30:00",
                summary: "模拟行情模式下的示例标题。",
                url: nil
            ),
            NewsHeadline(
                code: "MOCKN2",
                title: "（模拟）关注业绩与政策催化主线",
                mediaName: "模拟资讯",
                showTime: "2026-10-24 09:00:00",
                summary: "",
                url: nil
            ),
        ]
    }
}
