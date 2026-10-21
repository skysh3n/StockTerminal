import SwiftUI
import TradingCore

/// 涨跌 → 颜色 的唯一映射入口（A股习惯：红涨绿跌）。
/// 任何视图不得绕过 Sem 直接硬编码涨跌颜色，保证全局一致、未来切主题只改这里。
enum Sem {
    static var up: Color { .dsUp }
    static var down: Color { .dsDown }
    static var flat: Color { .dsFlat }

    /// 按涨跌幅（%）取色
    static func change(_ pct: Double?) -> Color {
        guard let pct else { return flat }
        if pct > 0.0001 { return up }
        if pct < -0.0001 { return down }
        return flat
    }

    /// 按价格相对参考价（昨收/成本）取色
    static func price(_ price: Decimal?, ref: Decimal?) -> Color {
        guard let price, let ref else { return flat }
        if price > ref { return up }
        if price < ref { return down }
        return flat
    }

    /// 按方向取色（外盘红 / 内盘绿）
    static func direction(_ dir: TickDirection) -> Color {
        switch dir {
        case .buy: return up
        case .sell: return down
        case .neutral: return flat
        }
    }

    /// 买卖方向取色（买红 / 卖绿）
    static func side(_ side: OrderSide) -> Color {
        side == .buy ? up : down
    }

    /// 委托状态取色
    static func status(_ status: OrderStatus) -> Color {
        switch status {
        case .filled: return up
        case .cancelled, .rejected: return .dsTextTertiary
        case .pending, .partialFilled, .cancelling: return .dsAccent
        }
    }
}
