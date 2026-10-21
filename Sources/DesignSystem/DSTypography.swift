import Foundation

/// 字体阶梯（单位 pt）。数字显示一律要求各平台使用等宽数字（monospaced digits），
/// 保证价格跳动时列不抖动——这是交易终端「专业感」的关键细节。
public enum DSFont {
    public static let micro: Double = 9.5     // 角标 / 列头 / 图例
    public static let caption: Double = 10     // 辅助标签
    public static let label: Double = 10.5     // 面板 eyebrow 标签
    public static let footnote: Double = 11    // 次级信息
    public static let body: Double = 12.5      // 终端密集基准
    public static let callout: Double = 13.5   // 强调正文
    public static let headline: Double = 15    // 面板标题 / 股票名
    public static let title: Double = 17       // 区块标题
    public static let bigNum: Double = 26      // 现价 / 账户资产大字
    public static let hero: Double = 30        // 特大数字

    /// 字重（跨平台数值语义：400 regular / 500 medium / 600 semibold / 700 bold）
    public enum Weight {
        public static let regular = 400
        public static let medium = 500
        public static let semibold = 600
        public static let bold = 700
    }
}
