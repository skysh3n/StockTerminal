import Foundation

/// 价格 / 条件预警判定（纯函数，便于单测）。
public enum AlertEvaluator {
    /// 若条件满足且尚未触发，返回应标记的触发时间；否则 nil。
    public static func shouldTrigger(
        alert: PriceAlert,
        lastPrice: Decimal,
        changePercent: Double,
        now: Date = Date()
    ) -> Date? {
        guard alert.enabled, alert.triggeredAt == nil else { return nil }
        switch alert.kind {
        case .absolutePrice:
            guard lastPrice > 0 else { return nil }
            switch alert.direction {
            case .above where lastPrice >= alert.threshold: return now
            case .below where lastPrice <= alert.threshold: return now
            default: return nil
            }
        case .dayChangeUp:
            let need = alert.threshold.doubleValue
            return changePercent >= need ? now : nil
        case .dayChangeDown:
            let need = alert.threshold.doubleValue
            return changePercent <= -need ? now : nil
        }
    }
}
