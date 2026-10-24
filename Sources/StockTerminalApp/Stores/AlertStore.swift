import Foundation
import Observation
import TradingCore

/// 本地价格预警：持久化到 Application Support，行情触及后 toast + 标记已触发。
@MainActor
@Observable
final class AlertStore {
    private(set) var alerts: [PriceAlert] = []
    /// 最近一次触发文案，供顶栏 toast 消费后清空。
    var pendingToast: String?

    private var evalTask: Task<Void, Never>?

    init() {
        alerts = Self.load() ?? []
    }

    func start(market: MarketStore) {
        evalTask?.cancel()
        evalTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.evaluate(against: market)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        evalTask?.cancel()
    }

    @discardableResult
    func add(symbol: String, name: String, direction: PriceAlertDirection, threshold: Decimal) -> Bool {
        guard threshold > 0 else { return false }
        let alert = PriceAlert(symbol: symbol, name: name, direction: direction, threshold: threshold)
        alerts.insert(alert, at: 0)
        persist()
        return true
    }

    func remove(_ id: UUID) {
        alerts.removeAll { $0.id == id }
        persist()
    }

    func toggle(_ id: UUID) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].enabled.toggle()
        if alerts[i].enabled { alerts[i].triggeredAt = nil }
        persist()
    }

    /// 已触发后允许「重新监视」同一规则。
    func reset(_ id: UUID) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].triggeredAt = nil
        alerts[i].enabled = true
        persist()
    }

    func evaluate(against market: MarketStore, now: Date = Date()) {
        var fired: [String] = []
        var dirty = false
        for i in alerts.indices {
            guard let q = market.states[alerts[i].symbol]?.quote else { continue }
            if let at = AlertEvaluator.shouldTrigger(alert: alerts[i], lastPrice: q.lastPrice, now: now) {
                alerts[i].triggeredAt = at
                dirty = true
                let a = alerts[i]
                fired.append("\(a.name) \(a.direction.label) \(Fmt.price(a.threshold))（现价 \(Fmt.price(q.lastPrice))）")
            }
        }
        if dirty { persist() }
        if let first = fired.first {
            pendingToast = fired.count == 1 ? "预警：\(first)" : "预警：\(first) 等 \(fired.count) 条"
        }
    }

    // MARK: - 持久化

    private struct Envelope: Codable {
        var alerts: [PriceAlert]
    }

    private static var url: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("StockTerminal", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("alerts.json")
    }

    private static func load() -> [PriceAlert]? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Envelope.self, from: data).alerts
    }

    private func persist() {
        guard let fileURL = Self.url else { return }
        let data = try? JSONEncoder().encode(Envelope(alerts: alerts))
        try? data?.write(to: fileURL, options: .atomic)
    }
}
