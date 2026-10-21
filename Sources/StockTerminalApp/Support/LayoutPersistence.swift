import AppKit
import SwiftUI

/// 终端布局尺寸：显式持久化到 UserDefaults（SwiftUI SplitView 的 autosave 嵌套时不可靠）。
@MainActor
@Observable
final class LayoutStore {
    var leftWidth: CGFloat
    var rightWidth: CGFloat
    /// 中间栏：图表高度占中间总高的比例
    var chartFraction: CGFloat
    /// 右栏：五档高度占「五档+逐笔」区域的比例
    var bookFraction: CGFloat
    var orderEntryCollapsed: Bool

    private static let defaults = UserDefaults.standard
    private static let leftKey = "layout.leftWidth"
    private static let rightKey = "layout.rightWidth"
    private static let chartKey = "layout.chartFraction"
    private static let bookKey = "layout.bookFraction"
    private static let collapseKey = "layout.orderEntryCollapsed"

    private var saveTask: Task<Void, Never>?

    init() {
        let d = Self.defaults
        leftWidth = Self.clamp(d.object(forKey: Self.leftKey) as? Double ?? 244, 200...420)
        rightWidth = Self.clamp(d.object(forKey: Self.rightKey) as? Double ?? 302, 260...440)
        chartFraction = Self.clamp(d.object(forKey: Self.chartKey) as? Double ?? 0.68, 0.35...0.85)
        bookFraction = Self.clamp(d.object(forKey: Self.bookKey) as? Double ?? 0.55, 0.30...0.80)
        orderEntryCollapsed = d.object(forKey: Self.collapseKey) as? Bool ?? false
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let d = Self.defaults
            d.set(Double(leftWidth), forKey: Self.leftKey)
            d.set(Double(rightWidth), forKey: Self.rightKey)
            d.set(Double(chartFraction), forKey: Self.chartKey)
            d.set(Double(bookFraction), forKey: Self.bookKey)
            d.set(orderEntryCollapsed, forKey: Self.collapseKey)
        }
    }

    func toggleOrderEntry() {
        withAnimation(.easeInOut(duration: 0.18)) {
            orderEntryCollapsed.toggle()
        }
        scheduleSave()
    }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> CGFloat {
        CGFloat(min(max(value, range.lowerBound), range.upperBound))
    }

    static func clamp(_ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension View {
    func windowFrameAutosave(_ name: String) -> some View {
        background(WindowFrameAutosave(name: name))
    }
}

// MARK: - 可拖分隔条

/// 横向拖动改宽度。`sign == 1`：向右拖变宽；`sign == -1`：向右拖变窄。
struct WidthDragDivider: View {
    @Binding var width: CGFloat
    var sign: CGFloat = 1
    var range: ClosedRange<CGFloat>
    var onSave: () -> Void

    @State private var dragOrigin: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(Color.dsBorder.opacity(0.4))
                    .frame(width: 1)
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragOrigin == nil { dragOrigin = width }
                        width = LayoutStore.clamp(
                            (dragOrigin ?? width) + sign * value.translation.width,
                            range
                        )
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        onSave()
                    }
            )
    }
}

/// 纵向拖动改比例（相对可用高度）。
struct FractionDragDivider: View {
    @Binding var fraction: CGFloat
    var totalHeight: CGFloat
    var range: ClosedRange<CGFloat>
    var onSave: () -> Void

    @State private var dragOrigin: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 5)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(Color.dsBorder.opacity(0.4))
                    .frame(height: 1)
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard totalHeight > 1 else { return }
                        if dragOrigin == nil { dragOrigin = fraction }
                        let delta = value.translation.height / totalHeight
                        fraction = LayoutStore.clamp(
                            (dragOrigin ?? fraction) + delta,
                            range
                        )
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        onSave()
                    }
            )
    }
}

private struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(name)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.setFrameAutosaveName(name)
        }
    }
}
