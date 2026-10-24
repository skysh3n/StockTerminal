import Foundation
import Observation
import TradingCore

/// 「榜单」工作区左栏模式（与自选完全分离）。
enum BoardListMode: String, CaseIterable, Identifiable {
    case gainers
    case losers
    case turnover
    case industry
    case concept
    case limitUp
    case billboard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gainers: return "涨幅"
        case .losers: return "跌幅"
        case .turnover: return "成交额"
        case .industry: return "行业"
        case .concept: return "概念"
        case .limitUp: return "涨停"
        case .billboard: return "龙虎榜"
        }
    }

    var rankKind: MarketRankKind? {
        switch self {
        case .gainers: return .gainers
        case .losers: return .losers
        case .turnover: return .turnover
        default: return nil
        }
    }

    var sectorKind: SectorKind? {
        switch self {
        case .industry: return .industry
        case .concept: return .concept
        default: return nil
        }
    }

    var isStockRanking: Bool { rankKind != nil }
    var isSectorMode: Bool { sectorKind != nil }
    var isLimitUp: Bool { self == .limitUp }
    var isBillboard: Bool { self == .billboard }
}

/// 看盘补充：A 股指数条 + 个股榜 + 行业/概念 + 涨停池 + 龙虎榜。
@MainActor
@Observable
final class MarketBoardStore {
    var listMode: BoardListMode = .gainers

    private(set) var indexQuotes: [String: Quote] = [:]

    // 个股榜
    private(set) var ranking: [MarketRankItem] = []
    private(set) var rankingKind: MarketRankKind = .gainers
    private(set) var rankingLoading = false
    private(set) var rankingError: String?

    // 板块
    private(set) var sectors: [SectorBoard] = []
    private(set) var sectorKind: SectorKind = .industry
    private(set) var activeSector: SectorBoard?
    private(set) var sectorConstituents: [MarketRankItem] = []
    private(set) var sectorLoading = false
    private(set) var sectorError: String?

    // 涨停池
    private(set) var limitUp: [MarketRankItem] = []
    private(set) var limitUpLoading = false
    private(set) var limitUpError: String?

    // 龙虎榜
    private(set) var billboard: [BillboardEntry] = []
    private(set) var billboardLoading = false
    private(set) var billboardError: String?

    // 当前选中标的资金流（分钟/日净流入摘要）
    private(set) var fundFlow: FundFlowSnapshot?
    private(set) var fundFlowLoading = false

    private var usingReal = false
    private var market: MarketStore?
    private var indexTask: Task<Void, Never>?
    private var fundFlowTask: Task<Void, Never>?
    private let rankClient = EastmoneyRankClient()
    private let sectorClient = EastmoneySectorClient()
    private let sinaSector = SinaSectorClient()
    private let limitUpClient = EastmoneyLimitUpClient()
    private let billboardClient = EastmoneyBillboardClient()
    private let fundFlowClient = EastmoneyFundFlowClient()
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

    /// 进入「榜单」工作区或切换左栏模式时调用。
    func applyMode(_ mode: BoardListMode) async {
        listMode = mode
        if let kind = mode.rankKind {
            await refreshRanking(kind: kind)
        } else if let sk = mode.sectorKind {
            await refreshSectors(kind: sk)
        } else if mode.isLimitUp {
            await refreshLimitUp()
        } else if mode.isBillboard {
            await refreshBillboard()
        }
    }

    func stop() {
        indexTask?.cancel()
    }

    // MARK: - 个股榜

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
                if ranking.isEmpty { ranking = mockRanking(kind: kind) }
            }
        } else {
            ranking = mockRanking(kind: kind)
        }
    }

    // MARK: - 板块

    func refreshSectors(kind: SectorKind) async {
        sectorKind = kind
        activeSector = nil
        sectorConstituents = []
        sectorLoading = true
        sectorError = nil
        defer { sectorLoading = false }

        if usingReal {
            do {
                sectors = try await sectorClient.sectors(kind: kind, limit: 40)
            } catch {
                // 东财 push2 偶发空响应 → 新浪兜底
                do {
                    switch kind {
                    case .industry:
                        sectors = try await sinaSector.industrySectors(limit: 40)
                    case .concept:
                        sectors = try await sinaSector.conceptSectors(limit: 16)
                    }
                    if sectors.isEmpty { sectorError = "板块暂时不可用" }
                } catch {
                    sectorError = "板块暂时不可用"
                    sectors = mockSectors(kind: kind)
                }
            }
        } else {
            sectors = mockSectors(kind: kind)
        }
    }

    func openSector(_ board: SectorBoard) async {
        activeSector = board
        sectorLoading = true
        sectorError = nil
        defer { sectorLoading = false }

        if usingReal {
            // 东财 BK 码走 clist；新浪 node 走新浪成分
            if board.sourceNode.hasPrefix("BK") {
                do {
                    sectorConstituents = try await sectorClient.constituents(boardCode: board.sourceNode, limit: 40)
                } catch {
                    sectorError = "成分股加载失败"
                    sectorConstituents = []
                }
            } else {
                do {
                    sectorConstituents = try await sinaSector.constituents(node: board.sourceNode, limit: 40)
                } catch {
                    sectorError = "成分股加载失败"
                    sectorConstituents = []
                }
            }
        } else {
            sectorConstituents = Array(mockRanking(kind: .gainers).prefix(20))
        }
    }

    func closeSector() {
        activeSector = nil
        sectorConstituents = []
    }

    // MARK: - 涨停池

    func refreshLimitUp() async {
        limitUpLoading = true
        limitUpError = nil
        defer { limitUpLoading = false }

        if usingReal {
            do {
                limitUp = try await limitUpClient.limitUpPool(limit: 50)
            } catch {
                limitUpError = "涨停池暂时不可用"
                if limitUp.isEmpty { limitUp = mockLimitUp() }
            }
        } else {
            limitUp = mockLimitUp()
        }
    }

    // MARK: - 龙虎榜

    func refreshBillboard() async {
        billboardLoading = true
        billboardError = nil
        defer { billboardLoading = false }
        if usingReal {
            do {
                billboard = try await billboardClient.daily(limit: 40)
            } catch {
                billboardError = "龙虎榜暂时不可用"
                if billboard.isEmpty { billboard = mockBillboard() }
            }
        } else {
            billboard = mockBillboard()
        }
    }

    // MARK: - 资金流

    func loadFundFlow(for fullCode: String?) {
        fundFlowTask?.cancel()
        guard let fullCode, !fullCode.isEmpty else {
            fundFlow = nil
            return
        }
        fundFlowLoading = true
        fundFlowTask = Task { [weak self] in
            guard let self else { return }
            defer { self.fundFlowLoading = false }
            if self.usingReal {
                self.fundFlow = try? await self.fundFlowClient.snapshot(fullCode: fullCode)
            } else {
                self.fundFlow = FundFlowSnapshot(
                    symbol: fullCode,
                    mainNetInflow: 12_500_000,
                    retailNetInflow: -8_200_000,
                    asOf: Date()
                )
            }
        }
    }

    // MARK: - 指数

    private func loopIndices() async {
        while !Task.isCancelled {
            await refreshIndices()
            let wait: Duration = MarketSession.phase().isActiveTrading ? .seconds(3) : .seconds(30)
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

    // MARK: - Mock

    private func mockRanking(kind: MarketRankKind) -> [MarketRankItem] {
        guard let market else { return [] }
        var items: [MarketRankItem] = []
        for state in market.states.values {
            guard let q = state.quote, q.lastPrice > 0 else { continue }
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
        case .gainers: items.sort { $0.changePercent > $1.changePercent }
        case .losers: items.sort { $0.changePercent < $1.changePercent }
        case .turnover: items.sort { $0.turnover > $1.turnover }
        }
        return Array(items.prefix(40))
    }

    private func mockSectors(kind: SectorKind) -> [SectorBoard] {
        let names: [String] = {
            switch kind {
            case .industry: return ["电子信息", "机械行业", "医药生物", "电力行业", "食品饮料"]
            case .concept: return ["人工智能", "新能源车", "半导体", "机器人", "低空经济"]
            }
        }()
        let base = mockRanking(kind: .gainers)
        return names.enumerated().map { idx, name in
            let lead = base[safe: idx]
            return SectorBoard(
                code: "MOCK\(idx)",
                name: name,
                changePercent: lead?.changePercent ?? Double(3 - idx) * 0.8,
                upCount: 12 - idx,
                downCount: 3 + idx,
                leadName: lead?.symbol.name ?? "—",
                leadChangePercent: lead?.changePercent ?? 0,
                sourceNode: "MOCK\(idx)"
            )
        }
    }

    private func mockLimitUp() -> [MarketRankItem] {
        mockRanking(kind: .gainers).filter {
            $0.changePercent + 0.05 >= EastmoneyLimitUpClient.limitThreshold(for: $0.symbol)
        }
    }

    private func mockBillboard() -> [BillboardEntry] {
        mockRanking(kind: .gainers).prefix(8).enumerated().map { idx, item in
            BillboardEntry(
                symbol: item.symbol,
                closePrice: item.lastPrice,
                changePercent: item.changePercent,
                netAmount: Decimal(idx % 2 == 0 ? 50_000_000 : -30_000_000),
                explanation: "（模拟）龙虎榜示例",
                tradeDate: "2026-10-23"
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
