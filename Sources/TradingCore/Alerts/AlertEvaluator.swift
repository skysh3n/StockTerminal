import Foundation

/// 价格预警判定（纯函数，便于单测）。
public enum AlertEvaluator {
    /// 若当前价触及阈值且尚未触发，返回应标记的触发时间；否则 nil。
    public static func shouldTrigger(
        alert: PriceAlert,
        lastPrice: Decimal,
        now: Date = Date()
    ) -> Date? {
        guard alert.enabled, alert.triggeredAt == nil, lastPrice > 0 else { return nil }
        switch alert.direction {
        case .above where lastPrice >= alert.threshold: return now
        case .below where lastPrice <= alert.threshold: return now
        default: return nil
        }
    }
}
