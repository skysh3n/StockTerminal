// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StockTerminal",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "StockTerminal", targets: ["StockTerminalApp"]),
        .executable(name: "tokens-export", targets: ["TokensExportTool"]),
        .library(name: "TradingCore", targets: ["TradingCore"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        // 纯逻辑核心层：模型、服务协议、模拟撮合、行情源。禁止 import SwiftUI/AppKit。
        // 平台相关编解码只放在 Platform/（GB18030）。
        .target(
            name: "TradingCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // 平台无关 design tokens（纯值），可导出 JSON 供 iOS/Windows/Linux 复用。
        .target(
            name: "DesignSystem",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // macOS SwiftUI 应用层
        .executableTarget(
            name: "StockTerminalApp",
            dependencies: ["TradingCore", "DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // 设计 tokens 导出工具：swift run tokens-export > tokens.json
        .executableTarget(
            name: "TokensExportTool",
            dependencies: ["DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TradingCoreTests",
            dependencies: ["TradingCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
