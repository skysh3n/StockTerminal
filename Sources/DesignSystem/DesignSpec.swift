import Foundation

/// 聚合全部 design tokens 的可序列化规范。
/// 这是设计语言的单一数据源：`swift run tokens-export > tokens.json`
/// 导出后，iOS / Windows / Linux 端各自读取并映射到原生颜色/字体/尺寸类型。
public struct DesignSpec: Codable, Sendable {
    public var name: String
    public var theme: String
    public var colors: [String: ColorToken]
    public var fontSizes: [String: Double]
    public var fontWeights: [String: Int]
    public var spacing: [String: Double]
    public var radii: [String: Double]
    public var strokes: [String: Double]
    /// 跨平台一致的语义约定（如涨跌配色方向、数字等宽要求）
    public var semantics: [String: String]

    public static let current = DesignSpec.make(theme: "dark", colors: DSColor.dark)

    public static let light = DesignSpec.make(theme: "light", colors: DSColor.light)

    private static func make(theme: String, colors: DSColorPalette) -> DesignSpec {
        DesignSpec(
        name: "StockTerminal",
        theme: theme,
        colors: colors.asDictionary,
        fontSizes: [
            "micro": DSFont.micro,
            "caption": DSFont.caption,
            "label": DSFont.label,
            "footnote": DSFont.footnote,
            "body": DSFont.body,
            "callout": DSFont.callout,
            "headline": DSFont.headline,
            "title": DSFont.title,
            "bigNum": DSFont.bigNum,
            "hero": DSFont.hero,
        ],
        fontWeights: [
            "regular": DSFont.Weight.regular,
            "medium": DSFont.Weight.medium,
            "semibold": DSFont.Weight.semibold,
            "bold": DSFont.Weight.bold,
        ],
        spacing: [
            "xxs": DSSpace.xxs, "xs": DSSpace.xs, "sm": DSSpace.sm, "md": DSSpace.md,
            "lg": DSSpace.lg, "xl": DSSpace.xl, "xxl": DSSpace.xxl,
        ],
        radii: ["sm": DSRadius.sm, "md": DSRadius.md, "lg": DSRadius.lg, "pill": DSRadius.pill],
        strokes: ["hairline": DSStroke.hairline, "regular": DSStroke.regular],
        semantics: [
            "upIsRed": "true",           // A股习惯：红涨绿跌
            "downIsGreen": "true",
            "digits": "monospaced",      // 所有数字必须等宽
            "language": "zh-CN",
        ]
        )
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public func jsonString() -> String {
        guard let data = try? jsonData(), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}
