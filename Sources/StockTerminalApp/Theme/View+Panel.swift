import SwiftUI
import DesignSystem

// MARK: - 容器体系（高级终端视觉语言）
//
// 双层容器（Double-Bezel）：外壳托盘 + 内层核心，两层圆角同心收敛，
// 内层带极轻的顶部内高光——模拟「玻璃面板嵌在铝托盘里」的物理层次。

extension View {
    /// 浮层卡片：面板底色 + 发丝描边 + 顶部内高光
    func terminalCard(radius: CGFloat = 10) -> some View {
        let sheen = ThemePaletteCache.isDark ? 0.028 : 0.04
        return self
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.dsPanel)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius)
                            .fill(LinearGradient(
                                colors: [Color.dsSheen.opacity(sheen), .clear],
                                startPoint: .top, endPoint: .center
                            ))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color.dsBorder.opacity(0.9), lineWidth: 0.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }

    /// 双层嵌套卡（Double-Bezel）：外层托盘 + 内层核心，同心圆角
    func bezel(radius: CGFloat = 12) -> some View {
        let sheen = ThemePaletteCache.isDark ? 0.035 : 0.05
        return self
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.dsPanel)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius)
                            .fill(LinearGradient(
                                colors: [Color.dsSheen.opacity(sheen), .clear],
                                startPoint: .top, endPoint: .center
                            ))
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .padding(3)
            .background(RoundedRectangle(cornerRadius: radius + 3).fill(Color.dsElevated.opacity(0.5)))
            .overlay(
                RoundedRectangle(cornerRadius: radius + 3)
                    .stroke(Color.dsBorderStrong.opacity(0.45), lineWidth: 0.6)
            )
    }

    /// 输入槽
    func inputBox(focused: Bool = false) -> some View {
        let inset = ThemePaletteCache.isDark ? 0.15 : 0.04
        return background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.dsInput)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.dsSheen.opacity(inset))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(focused ? Color.dsAccent.opacity(0.65) : Color.dsBorder,
                        lineWidth: focused ? 1 : 0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - 面板标题（eyebrow 风格）

struct PanelHeader<Trailing: View>: View {
    let title: String
    /// 自选 / 榜单等主模块标题加大一号，更易扫读。
    var prominent: Bool = false
    @ViewBuilder var trailing: Trailing

    init(_ title: String, prominent: Bool = false, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.prominent = prominent
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 1,
                                   bottomTrailingRadius: 1, topTrailingRadius: 1)
                .fill(Color.dsAccent.opacity(0.85))
                .frame(width: 2.5, height: prominent ? 14 : 9)
            Text(title)
                .font(prominent ? .dsCallout(medium: true) : .dsLabel(medium: true))
                .tracking(prominent ? 0.2 : 0.5)
                .foregroundStyle(prominent ? Color.dsTextPrimary : Color.dsTextSecondary)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, prominent ? 9 : 7)
    }
}

// MARK: - 标签 / 徽章

/// 方形小标签（克制的 pastel 底 + 描边，替代胶囊徽章）
struct Tag: View {
    let text: String
    var color: Color = .dsTextSecondary

    var body: some View {
        Text(text)
            .font(.dsMicro(medium: true))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(color.opacity(0.16), lineWidth: 0.6)
            )
    }
}

/// 涨跌幅徽章：实色底 + 顶部内高光 + 发丝描边（A股终端经典，但做精）
struct ChangeChip: View {
    let text: String
    let color: Color
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 10 : 11, weight: .semibold).monospacedDigit())
            .tracking(0.2)
            .foregroundStyle(.white.opacity(0.96))
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 1.5 : 2.5)
            .frame(minWidth: compact ? 52 : 62)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(
                        colors: [color, color.opacity(0.82)],
                        startPoint: .top, endPoint: .bottom
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.16), lineWidth: 0.5)
            )
    }
}

// MARK: - 交互

/// 按压反馈：微缩放 + 轻微降透明（只在实际按压时驱动一次动画）。
/// 强制整块 label 可点：`frame(maxWidth:)` 扩出来的空白默认不命中。
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 行 hover：内缩圆角浮层（列表行通用）
struct HoverBackground: ViewModifier {
    var selected: Bool = false
    var radius: CGFloat = 6
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(selected ? Color.dsElevated
                          : hovering ? Color.dsHover.opacity(0.65) : .clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.dsAccent)
                        .frame(width: 2, height: 16)
                        .padding(.leading, 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

extension View {
    func rowHover(selected: Bool = false, radius: CGFloat = 6) -> some View {
        modifier(HoverBackground(selected: selected, radius: radius))
    }
}

// MARK: - 空态

/// 空态：空间够时带图标，面板被压矮时只留一行文字，不会被裁切。
struct EmptyHint: View {
    let text: String

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 10) {
                icon
                label
            }
            .padding(12)

            label
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.dsElevated.opacity(0.7))
                .frame(width: 34, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.dsBorderStrong.opacity(0.5), lineWidth: 0.6)
                )
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(Color.dsTextTertiary)
        }
    }

    private var label: some View {
        Text(text)
            .font(.dsFootnote())
            .foregroundStyle(Color.dsTextTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}
