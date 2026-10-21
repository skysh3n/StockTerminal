import Foundation
import Observation
import SwiftUI

/// 图表视口状态：缩放（可见根数）/ 平移（距最新偏移）/ 悬停位置。
/// 高频交互状态独立成对象：十字光标层单独观察 hoverPoint，不牵动主图重绘。
@MainActor
@Observable
final class Viewport {
    /// 可见 bar 根数（缩放）
    var visibleCount: Int = 120
    /// 距最新 bar 的偏移（平移；0 = 跟随最新）
    var offsetFromEnd: Int = 0
    /// 鼠标悬停位置（图表局部坐标）
    var hoverPoint: CGPoint?
    /// 手势起始基准
    var panStartOffset: Int?
    var pinchStartCount: Int?

    func reset() {
        visibleCount = 120
        offsetFromEnd = 0
        hoverPoint = nil
        panStartOffset = nil
        pinchStartCount = nil
    }

    /// 滚轮缩放：上滚放大（可见根数变少）
    func wheelZoom(deltaY: CGFloat) {
        let factor: Double = deltaY > 0 ? 0.88 : 1.12
        visibleCount = min(max(Int((Double(visibleCount) * factor).rounded()), 20), 600)
    }

    /// 拖拽平移：右拖看历史
    func pan(translationX: CGFloat, spacing: CGFloat, totalBars: Int) {
        if panStartOffset == nil { panStartOffset = offsetFromEnd }
        let moved = Int(translationX / max(spacing, 0.5))
        let maxOffset = max(0, totalBars - visibleCount)
        offsetFromEnd = min(max((panStartOffset ?? 0) + moved, 0), maxOffset)
    }

    /// 捏合缩放
    func pinch(magnification: Double) {
        if pinchStartCount == nil { pinchStartCount = visibleCount }
        let start = Double(pinchStartCount ?? 120)
        visibleCount = min(max(Int(start / max(magnification, 0.1)), 20), 600)
    }
}
