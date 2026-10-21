import AppKit
import SwiftUI

/// 鼠标滚轮缩放捕获层。
/// 实现：NSEvent 本地监视器 + hitTest 返回 nil（完全穿透，不影响 SwiftUI 手势）。
/// 只有鼠标位于本视图屏幕范围内时才消费滚轮事件。
struct WheelCatcher: NSViewRepresentable {
    let onWheel: @MainActor (CGFloat) -> Void

    func makeNSView(context: Context) -> WheelCatcherNSView {
        let v = WheelCatcherNSView()
        v.box.onWheel = onWheel
        return v
    }

    func updateNSView(_ nsView: WheelCatcherNSView, context: Context) {
        nsView.box.onWheel = onWheel
    }
}

/// 主线程访问的 Sendable 桥接盒（NSEvent 监视器回调要求 @Sendable，NSView 本身不是）
final class WheelBox: @unchecked Sendable {
    weak var view: WheelCatcherNSView?
    var onWheel: (@MainActor (CGFloat) -> Void)?
}

final class WheelCatcherNSView: NSView {
    let box = WheelBox()
    /// 仅主线程访问；deinit 清理需要 nonisolated 访问
    private nonisolated(unsafe) var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        box.view = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        let box = self.box
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // assumeIsolated 的返回值必须是 Sendable —— 只回传 Bool，事件对象留在外层
            let handled: Bool = MainActor.assumeIsolated {
                guard let view = box.view, let window = view.window, let onWheel = box.onWheel else {
                    return false
                }
                let frameInWindow = view.convert(view.bounds, to: nil)
                let screenFrame = window.convertToScreen(frameInWindow)
                guard screenFrame.contains(NSEvent.mouseLocation) else { return false }
                let dy = event.scrollingDeltaY
                guard abs(dy) > 0.01 else { return false }
                onWheel(dy)
                return true
            }
            return handled ? nil : event
        }
    }

    /// 穿透：不参与命中测试，SwiftUI 拖拽/悬停手势不受影响
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func removeMonitor() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }
}
