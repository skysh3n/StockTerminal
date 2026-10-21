import Foundation
import Observation
import TradingCore

/// 账户资产 + 持仓
@MainActor
@Observable
final class PortfolioStore {
    private(set) var snapshot: AccountSnapshot?
    private(set) var positions: [Position] = []

    private let svc: any AccountService
    private var tasks: [Task<Void, Never>] = []

    init(_ svc: any AccountService) {
        self.svc = svc
    }

    func start() async {
        snapshot = try? await svc.snapshot()
        positions = (try? await svc.positions()) ?? []

        let ss = svc.subscribeSnapshot()
        tasks.append(Task { [weak self] in
            for await s in ss { self?.snapshot = s }
        })
        let ps = svc.subscribePositions()
        tasks.append(Task { [weak self] in
            for await p in ps { self?.positions = p }
        })
    }

    func position(for code: String) -> Position? {
        positions.first { $0.symbol == code }
    }
}
