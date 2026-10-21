import SwiftUI
import DesignSystem

// MARK: - DSTypography → SwiftUI Font 绑定
// 所有数字场景一律 monospacedDigit：价格跳动时列不抖动（专业感/流畅感的关键细节）

extension Font {
    static func dsMicro(medium: Bool = false) -> Font {
        .system(size: DSFont.micro, weight: medium ? .medium : .regular).monospacedDigit()
    }

    static func dsCaption(medium: Bool = false) -> Font {
        .system(size: DSFont.caption, weight: medium ? .medium : .regular).monospacedDigit()
    }

    static func dsLabel(medium: Bool = false) -> Font {
        .system(size: DSFont.label, weight: medium ? .medium : .regular).monospacedDigit()
    }

    static func dsFootnote(medium: Bool = false) -> Font {
        .system(size: DSFont.footnote, weight: medium ? .medium : .regular).monospacedDigit()
    }

    static func dsBody(medium: Bool = false) -> Font {
        .system(size: DSFont.body, weight: medium ? .medium : .regular).monospacedDigit()
    }

    static func dsCallout(medium: Bool = false) -> Font {
        .system(size: DSFont.callout, weight: medium ? .medium : .regular).monospacedDigit()
    }

    static func dsHeadline(medium: Bool = false) -> Font {
        .system(size: DSFont.headline, weight: medium ? .semibold : .medium).monospacedDigit()
    }

    static func dsTitle() -> Font {
        .system(size: DSFont.title, weight: .semibold).monospacedDigit()
    }

    static func dsBigNum() -> Font {
        .system(size: DSFont.bigNum, weight: .semibold).monospacedDigit()
    }
    static func dsHero() -> Font {
        .system(size: DSFont.hero, weight: .bold).monospacedDigit()
    }
}
