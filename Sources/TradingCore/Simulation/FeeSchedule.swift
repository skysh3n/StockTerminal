import Foundation

/// A股费用表：佣金（双向，最低5元）+ 印花税（卖出）+ 过户费（沪市双向）
public struct FeeSchedule: Sendable {
    public var commissionRate: Decimal = Decimal(string: "0.00025")!
    public var minCommission: Decimal = 5
    public var stampTaxRate: Decimal = Decimal(string: "0.0005")!   // 仅卖出
    public var transferFeeRate: Decimal = Decimal(string: "0.00001")! // 仅沪市
    /// 买入冻结资金估算上浮系数
    public var freezeBufferRate: Decimal = Decimal(string: "1.0005")!

    public init() {}

    public func fee(side: OrderSide, notional: Decimal, exchange: Exchange) -> Decimal {
        var f = max(notional * commissionRate, minCommission)
        if side == .sell { f += notional * stampTaxRate }
        if exchange == .sse { f += notional * transferFeeRate }
        return f.quantized(to: Decimal(string: "0.01")!)
    }
}
