import SwiftUI
import DesignSystem

// MARK: - ColorToken → SwiftUI Color 绑定
// 色值来自 ThemePaletteCache（切换主题时由 ThemeStore 写入），根视图 .id 触发重绘。

extension Color {
    init(_ token: ColorToken) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: token.alpha)
    }

    private static var p: DSColorPalette { ThemePaletteCache.palette }

    // 背景层次
    static var dsBgBase: Color { Color(p.bgBase) }
    static var dsPanel: Color { Color(p.bgPanel) }
    static var dsElevated: Color { Color(p.bgElevated) }
    static var dsInput: Color { Color(p.bgInput) }
    static var dsHover: Color { Color(p.hover) }
    static var dsShadow: Color { Color(p.shadow) }

    // 描边
    static var dsBorder: Color { Color(p.border) }
    static var dsBorderStrong: Color { Color(p.borderStrong) }

    // 文字
    static var dsTextPrimary: Color { Color(p.textPrimary) }
    static var dsTextSecondary: Color { Color(p.textSecondary) }
    static var dsTextTertiary: Color { Color(p.textTertiary) }

    // 涨跌 / 强调
    static var dsUp: Color { Color(p.up) }
    static var dsDown: Color { Color(p.down) }
    static var dsFlat: Color { Color(p.flat) }
    static var dsAccent: Color { Color(p.accent) }
    static var dsInfo: Color { Color(p.info) }
    static var dsWarning: Color { Color(p.warning) }

    // 均线
    static var dsMA5: Color { Color(p.ma5) }
    static var dsMA10: Color { Color(p.ma10) }
    static var dsMA20: Color { Color(p.ma20) }
    static var dsMA60: Color { Color(p.ma60) }

    /// 面板顶部高光（深色白 / 浅色黑）
    static var dsSheen: Color {
        ThemePaletteCache.isDark ? .white : .black
    }
}
