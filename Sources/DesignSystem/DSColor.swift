import Foundation

/// 一套完整色板（深色 / 浅色各一份）。App 层按当前主题取色；tokens.json 仍可导出。
public struct DSColorPalette: Codable, Sendable, Hashable {
    public var bgBase: ColorToken
    public var bgPanel: ColorToken
    public var bgElevated: ColorToken
    public var bgInput: ColorToken
    public var hover: ColorToken
    public var border: ColorToken
    public var borderStrong: ColorToken
    public var textPrimary: ColorToken
    public var textSecondary: ColorToken
    public var textTertiary: ColorToken
    public var up: ColorToken
    public var down: ColorToken
    public var flat: ColorToken
    public var accent: ColorToken
    public var info: ColorToken
    public var warning: ColorToken
    public var ma5: ColorToken
    public var ma10: ColorToken
    public var ma20: ColorToken
    public var ma60: ColorToken
    public var shadow: ColorToken

    public var asDictionary: [String: ColorToken] {
        [
            "bgBase": bgBase, "bgPanel": bgPanel, "bgElevated": bgElevated,
            "bgInput": bgInput, "hover": hover,
            "border": border, "borderStrong": borderStrong,
            "textPrimary": textPrimary, "textSecondary": textSecondary, "textTertiary": textTertiary,
            "up": up, "down": down, "flat": flat,
            "accent": accent, "info": info, "warning": warning,
            "ma5": ma5, "ma10": ma10, "ma20": ma20, "ma60": ma60,
            "shadow": shadow,
        ]
    }
}

/// 设计系统色板入口：`dark` / `light`。兼容旧代码的 `DSColor.bgBase` 等仍指向深色默认值。
public enum DSColor {
    /// 深色交易终端：冷调炭黑 + 金色强调；涨跌降饱和。
    public static let dark = DSColorPalette(
        bgBase: ColorToken(0x07090C),
        bgPanel: ColorToken(0x0D1015),
        bgElevated: ColorToken(0x151A21),
        bgInput: ColorToken(0x0A0D11),
        hover: ColorToken(0x1A2028),
        border: ColorToken(0x1E242C),
        borderStrong: ColorToken(0x2B323C),
        textPrimary: ColorToken(0xE9ECF1),
        textSecondary: ColorToken(0x9AA3AE),
        textTertiary: ColorToken(0x5B6470),
        up: ColorToken(0xE5484D),
        down: ColorToken(0x0FA37F),
        flat: ColorToken(0x7A838F),
        accent: ColorToken(0xE0A540),
        info: ColorToken(0x4D86E8),
        warning: ColorToken(0xE08B3F),
        ma5: ColorToken(0xE0A540),
        ma10: ColorToken(0x4D86E8),
        ma20: ColorToken(0xA68BF0),
        ma60: ColorToken(0xD9DEE6),
        shadow: ColorToken(0x020307)
    )

    /// 浅色交易终端：冷灰纸面 + 白卡片；涨跌略加深以保证对比。
    public static let light = DSColorPalette(
        bgBase: ColorToken(0xE8ECF1),
        bgPanel: ColorToken(0xFFFFFF),
        bgElevated: ColorToken(0xF3F5F8),
        bgInput: ColorToken(0xF0F2F5),
        hover: ColorToken(0xE2E7ED),
        border: ColorToken(0xD0D7E0),
        borderStrong: ColorToken(0xB4BDC9),
        textPrimary: ColorToken(0x1A1F27),
        textSecondary: ColorToken(0x5A6572),
        textTertiary: ColorToken(0x8A94A1),
        up: ColorToken(0xD6353F),
        down: ColorToken(0x0B8F6E),
        flat: ColorToken(0x6B7380),
        accent: ColorToken(0xC9922A),
        info: ColorToken(0x3B74D4),
        warning: ColorToken(0xD07A2E),
        ma5: ColorToken(0xC9922A),
        ma10: ColorToken(0x3B74D4),
        ma20: ColorToken(0x8B6FD4),
        ma60: ColorToken(0x5A6572),
        shadow: ColorToken(0x1A2330)
    )

    // MARK: - 兼容旧引用（默认深色静态值，供 DesignSpec / 导出工具）

    public static let bgBase = dark.bgBase
    public static let bgPanel = dark.bgPanel
    public static let bgElevated = dark.bgElevated
    public static let bgInput = dark.bgInput
    public static let hover = dark.hover
    public static let border = dark.border
    public static let borderStrong = dark.borderStrong
    public static let textPrimary = dark.textPrimary
    public static let textSecondary = dark.textSecondary
    public static let textTertiary = dark.textTertiary
    public static let up = dark.up
    public static let down = dark.down
    public static let flat = dark.flat
    public static let accent = dark.accent
    public static let info = dark.info
    public static let warning = dark.warning
    public static let ma5 = dark.ma5
    public static let ma10 = dark.ma10
    public static let ma20 = dark.ma20
    public static let ma60 = dark.ma60
    public static let shadow = dark.shadow
}
