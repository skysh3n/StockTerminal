import Foundation
import Observation
import TradingCore

/// 看盘补充：A 股指数条 + 全市场榜单。真实行情走公开接口；Mock 用已有报价池排序。
@MainActor
@Observable
final class MarketBoardStore {
    private(set) var indexQuotes: [String: Quote] = [:]
    private(set) var ranking: [MarketRankItem] = []
    private(set) var rankingKind: MarketRankKind = .gainers
    private(set) var rankingLoading = false
    private(set) var rankingError: String?

    private var usingReal = false
    private var market: MarketStore?
    private var indexTask: Task<Void, Never>?
    private var rankTask: Task<Void, Never>?
    private let rankClient = EastmoneyRankClient()
    private let tencent = TencentMarketClient()

    func start(usingRealMarket: Bool, market: MarketStore) {
        self.usingReal = usingRealMarket
        self.market = market
        indexTask?.cancel()
        indexTask = Task { [weak self] in
            await self?.loopIndices()
        }
        Task { await refreshRanking(kind: .gainers) }
    }

    func stop() {
        indexTask?.cancel()
        rankTask?.cancel()
    }

    func refreshRanking(kind: MarketRankKind) async {
        rankingKind = kind
        rankingLoading = true
        rankingError = nil
        defer { rankingLoading = false }

        if usingReal {
            do {
                ranking = try await rankClient.ranking(kind: kind, limit: 40)
            } catch {
                rankingError = "榜单暂时不可用"
                if ranking.isEmpty {
                    ranking = mockRanking(kind: kind)
                }
            }
        } else {
            ranking = mockRanking(kind: kind)
        }
    }

    private func loopIndices() async {
        while !Task.isCancelled {
            await refreshIndices()
            let wait: Duration = MarketSession.isOpen() ? .seconds(3) : .seconds(30)
            try? await Task.sleep(for: wait)
        }
    }

    private func refreshIndices() async {
        if usingReal {
            if let snaps = try? await tencent.snapshots(for: AShareIndices.all) {
                var map: [String: Quote] = [:]
                for snap in snaps { map[snap.quote.symbol] = snap.quote }
                if !map.isEmpty { indexQuotes = map }
            }
        } else if let market {
            // Mock：指数用池内前三只报价冒充，保证离线条带有跳动
            var map: [String: Quote] = [:]
            for (idx, index) in AShareIndices.all.enumerated() {
                let pool = Array(market.states.values)
                guard idx < pool.count, let q = pool[idx].quote else { continue }
                map[index.fullCode] = Quote(
                    symbol: index.fullCode,
                    lastPrice: q.lastPrice,
                    open: q.open,
                    high: q.high,
                    low: q.low,
                    preClose: q.preClose,
                    bidPrice1: q.bidPrice1,
                    askPrice1: q.askPrice1,
                    bidVolume1: 0,
                    askVolume1: 0,
                    volume: q.volume,
                    turnover: q.turnover,
                    upperLimit: 0,
                    lowerLimit: 0,
                    timestamp: q.timestamp
                )
            }
            if !map.isEmpty { indexQuotes = map }
        }
    }

    private func mockRanking(kind: MarketRankKind) -> [MarketRankItem] {
        guard let market else { return [] }
        var items: [MarketRankItem] = []
        for state in market.states.values {
            guard let q = state.quote, q.lastPrice > 0 else { continue }
            // 指数代码不进个股榜
            if AShareIndices.codes.contains(state.symbol.fullCode) { continue }
            items.append(MarketRankItem(
                symbol: state.symbol,
                lastPrice: q.lastPrice,
                changePercent: q.changePercent,
                change: q.change,
                volumeLots: q.volume / 100,
                turnover: q.turnover
            ))
        }
        switch kind {
        case .gainers:
            items.sort { $0.changePercent > $1.changePercent }
        case .losers:
            items.sort { $0.changePercent < $1.changePercent }
        case .turnover:
            items.sort { $0.turnover > $1.turnover }
        }
        return Array(items.prefix(40))
    }
}
