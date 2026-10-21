import Foundation

/// 统一业务错误类型。真实 adapter 应将后端错误映射到这些语义化 case。
public enum ServiceError: Error, Sendable, Equatable {
    case symbolNotFound(String)
    case insufficientCash(required: Decimal, available: Decimal)
    case insufficientShares(required: Int, available: Int)
    case invalidQuantity(Int)                 // 非整手 / 非正数
    case priceOutOfLimit(Decimal)             // 超出涨跌停
    case orderNotFound(String)
    case orderNotCancellable(String)
    case backend(String)

    /// 面向用户的中文提示
    public var message: String {
        switch self {
        case .symbolNotFound(let code):
            return "未找到证券 \(code)"
        case .insufficientCash(let required, let available):
            return "资金不足：需要 \(required.moneyText)，可用 \(available.moneyText)"
        case .insufficientShares(let required, let available):
            return "可卖股数不足：需要 \(required)，可用 \(available)"
        case .invalidQuantity(let qty):
            return "委托数量无效（\(qty)），买入必须为 100 股整数倍"
        case .priceOutOfLimit(let price):
            return "委托价 \(price.moneyText) 超出涨跌停范围"
        case .orderNotFound(let id):
            return "委托不存在：\(id)"
        case .orderNotCancellable(let id):
            return "委托 \(id) 当前状态不可撤单"
        case .backend(let msg):
            return msg
        }
    }
}

extension Decimal {
    /// 错误提示用的简单金额文案
    var moneyText: String { String(format: "%.2f", doubleValue) }
}
