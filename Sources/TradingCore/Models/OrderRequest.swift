import Foundation

/// 下单入参
public struct OrderRequest: Sendable, Hashable {
    public let clientOrderId: String
    public let symbol: String        // 完整代码
    public let side: OrderSide
    public let type: OrderType
    public let price: Decimal?       // 限价必填；市价传 nil
    public let quantity: Int         // 股；买入必须为整手

    public init(
        clientOrderId: String = UUID().uuidString,
        symbol: String,
        side: OrderSide,
        type: OrderType,
        price: Decimal?,
        quantity: Int
    ) {
        self.clientOrderId = clientOrderId
        self.symbol = symbol
        self.side = side
        self.type = type
        self.price = price
        self.quantity = quantity
    }
}
