import Foundation

/// 委托单
public struct Order: Codable, Sendable, Hashable, Identifiable {
    public let id: String                 // 委托编号
    public let clientOrderId: String
    public let symbol: String
    public let name: String
    public var side: OrderSide
    public var type: OrderType
    public var price: Decimal?            // 限价单价格；市价单为 nil
    public var quantity: Int              // 委托量（股）
    public var filledQuantity: Int
    public var filledAvgPrice: Decimal?
    public var status: OrderStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String, clientOrderId: String, symbol: String, name: String,
        side: OrderSide, type: OrderType, price: Decimal?, quantity: Int,
        filledQuantity: Int = 0, filledAvgPrice: Decimal? = nil,
        status: OrderStatus = .pending, createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.clientOrderId = clientOrderId
        self.symbol = symbol
        self.name = name
        self.side = side
        self.type = type
        self.price = price
        self.quantity = quantity
        self.filledQuantity = filledQuantity
        self.filledAvgPrice = filledAvgPrice
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 未成交数量
    public var remainingQuantity: Int { quantity - filledQuantity }

    /// 委托金额（按委托价或成交均价）
    public var orderAmount: Decimal {
        (price ?? filledAvgPrice ?? 0) * Decimal(quantity)
    }
}

/// 成交回报
public struct Trade: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let orderId: String
    public let symbol: String
    public let name: String
    public let side: OrderSide
    public let price: Decimal
    public let quantity: Int
    public let fee: Decimal
    public let timestamp: Date

    public init(id: String, orderId: String, symbol: String, name: String, side: OrderSide, price: Decimal, quantity: Int, fee: Decimal, timestamp: Date) {
        self.id = id
        self.orderId = orderId
        self.symbol = symbol
        self.name = name
        self.side = side
        self.price = price
        self.quantity = quantity
        self.fee = fee
        self.timestamp = timestamp
    }

    public var amount: Decimal { price * Decimal(quantity) }
}
