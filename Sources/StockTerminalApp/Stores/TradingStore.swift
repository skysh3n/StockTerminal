import Foundation
import Observation
import TradingCore

/// 下单面板草稿（表单状态）
@MainActor
@Observable
final class OrderDraft {
    var symbolCode: String = ""
    var symbolName: String = ""
    var side: OrderSide = .buy
    var type: OrderType = .limit
    var priceText: String = ""
    var qtyText: String = "100"

    /// 切换标的时重置表单；同一标的保留用户输入
    func setSymbol(code: String, name: String, refPrice: Decimal?) {
        guard symbolCode != code else { return }
        symbolCode = code
        symbolName = name
        if let refPrice {
            priceText = String(format: "%.2f", refPrice.doubleValue)
        } else {
            priceText = ""
        }
        qtyText = "100"
        side = .buy
        type = .limit
    }

    var price: Decimal? {
        let cleaned = priceText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned)
    }

    var quantity: Int? {
        Int(qtyText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ""))
    }
}

/// 交易状态：委托/成交列表 + 下单动作 + 全局提示
@MainActor
@Observable
final class TradingStore {
    struct ToastMessage: Equatable {
        let text: String
        let isError: Bool
    }

    private(set) var orders: [Order] = []   // 新→旧
    private(set) var trades: [Trade] = []   // 新→旧
    var toast: ToastMessage?
    let draft = OrderDraft()

    private let svc: any TradingService
    private var tasks: [Task<Void, Never>] = []
    private var toastSeq = 0

    init(_ svc: any TradingService) {
        self.svc = svc
    }

    func start() async {
        orders = (try? await svc.allOrders()) ?? []
        trades = (try? await svc.trades()) ?? []

        let orderStream = svc.subscribeOrderUpdates()
        tasks.append(Task { [weak self] in
            for await o in orderStream {
                self?.upsertOrder(o)
            }
        })
        let tradeStream = svc.subscribeTradeUpdates()
        tasks.append(Task { [weak self] in
            for await t in tradeStream {
                self?.insertTrade(t)
            }
        })
    }

    var openOrderCount: Int { orders.filter { $0.status.isCancellable }.count }

    func place(_ req: OrderRequest) async {
        do {
            let order = try await svc.placeOrder(req)
            let detail = order.status == .filled
                ? "已成交 \(order.filledQuantity)股"
                : "已报单 \(order.quantity)股"
            showToast("\(order.name) \(order.side.label) \(detail)", isError: false)
        } catch {
            let msg = (error as? ServiceError)?.message ?? "下单失败：\(error.localizedDescription)"
            showToast(msg, isError: true)
        }
    }

    func cancel(id: String) async {
        do {
            try await svc.cancelOrder(id: id)
            showToast("撤单成功", isError: false)
        } catch {
            let msg = (error as? ServiceError)?.message ?? "撤单失败"
            showToast(msg, isError: true)
        }
    }

    // MARK: - 内部

    private func upsertOrder(_ o: Order) {
        if let idx = orders.firstIndex(where: { $0.id == o.id }) {
            orders[idx] = o
        } else {
            orders.insert(o, at: 0)
        }
    }

    private func insertTrade(_ t: Trade) {
        trades.insert(t, at: 0)
        if trades.count > 300 { trades.removeLast(trades.count - 300) }
    }

    func showToast(_ text: String, isError: Bool = false) {
        toastSeq += 1
        let seq = toastSeq
        toast = ToastMessage(text: text, isError: isError)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard let self, self.toastSeq == seq else { return }
            self.toast = nil
        }
    }
}
