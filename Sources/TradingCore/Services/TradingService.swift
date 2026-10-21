import Foundation

/// 交易服务协议（跨平台预留的核心边界之一）。
/// 未来接真实券商柜台/API 时只需实现本协议的 adapter。
public protocol TradingService: Sendable {
    /// 下单，返回委托单（含初始状态）
    @discardableResult
    func placeOrder(_ request: OrderRequest) async throws -> Order

    /// 撤单
    func cancelOrder(id: String) async throws

    /// 当前可撤委托
    func openOrders() async throws -> [Order]

    /// 当日全部委托（新→旧）
    func allOrders() async throws -> [Order]

    /// 当日全部成交（新→旧）
    func trades() async throws -> [Trade]

    /// 委托状态变化推送
    func subscribeOrderUpdates() -> AsyncStream<Order>

    /// 成交回报推送
    func subscribeTradeUpdates() -> AsyncStream<Trade>
}
