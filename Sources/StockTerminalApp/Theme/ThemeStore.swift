import AppKit
import Observation
import SwiftUI
import DesignSystem

enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: return "深色"
        case .light: return "浅色"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }

    var palette: DSColorPalette {
        switch self {
        case .dark: return DSColor.dark
        case .light: return DSColor.light
        }
    }
}

/// 供 `Color.ds*` 在非隔离上下文读取的当前色板（切换主题时同步写入）。
enum ThemePaletteCache {
    nonisolated(unsafe) static var theme: AppTheme = .dark
    nonisolated(unsafe) static var palette: DSColorPalette = DSColor.dark
}

/// 当前主题。切换后根视图用 `.id(theme)` 强制整树重绘。
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var theme: AppTheme

    var palette: DSColorPalette { theme.palette }

    var highlightOpacity: Double { theme == .dark ? 0.028 : 0.04 }
    var bezelHighlightOpacity: Double { theme == .dark ? 0.035 : 0.05 }
    var inputInsetOpacity: Double { theme == .dark ? 0.15 : 0.04 }

    private static let storageKey = "app.theme"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let saved = AppTheme(rawValue: raw) {
            theme = saved
        } else {
            theme = .dark
        }
        ThemePaletteCache.theme = theme
        ThemePaletteCache.palette = theme.palette
        // 不在 init 里碰 NSApp：App.init / shared 懒加载时 NSApp 可能尚未就绪。
    }

    func set(_ theme: AppTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        ThemePaletteCache.theme = theme
        ThemePaletteCache.palette = theme.palette
        UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey)
        applySystemAppearance()
    }

    func toggle() {
        set(theme == .dark ? .light : .dark)
    }

    /// 由 AppDelegate 在 applicationDidFinishLaunching 调用；切换主题时也会调用。
    func applySystemAppearance() {
        guard NSApp != nil else { return }
        NSApp.appearance = theme.nsAppearance
    }
}
