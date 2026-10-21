import Foundation

/// 金额精度工具：价格全程用 Decimal，只在渲染边界转 Double/CGFloat。
public extension Decimal {
    /// Decimal → Double（渲染/布局用）
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// 取整到最小变动价位（0.01），四舍五入（plain = 半值远离零）
    func quantized(to tick: Decimal) -> Decimal {
        guard tick > 0 else { return self }
        var raw = self / tick
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        return rounded * tick
    }

    /// Double → Decimal 并按 tick 规整（避免二进制浮点尾差）
    static func fromDouble(_ value: Double, tick: Decimal) -> Decimal {
        Decimal(value).quantized(to: tick)
    }
}

public extension Int64 {
    /// 股 → 手
    var lots: Int64 { self / 100 }
}
