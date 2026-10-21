import Foundation

/// 平台无关的颜色 token：只存 hex + alpha。
/// 各平台 UI 层（SwiftUI / UIKit / WinUI / GTK）自行绑定到原生颜色类型，
/// 配合 `DesignSpec` 导出的 tokens.json 保证跨平台设计语言一致。
public struct ColorToken: Codable, Sendable, Hashable {
    public let hex: UInt32 // 0xRRGGBB
    public let alpha: Double

    public init(_ hex: UInt32, alpha: Double = 1) {
        self.hex = hex
        self.alpha = alpha
    }

    public var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(hex & 0xFF) / 255 }

    public var hexString: String { String(format: "#%06X", hex) }
}
