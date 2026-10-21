import AppKit
import Observation
import SwiftUI
import DesignSystem

enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light
    case auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: return "深色"
        case .light: return "浅色"
        case .auto: return "自动"
        }
    }

    var iconName: String {
        switch self {
        case .dark: return "moon"
        case .light: return "sun.max"
        case .auto: return "circle.lefthalf.filled"
        }
    }
}

/// 供 `Color.ds*` 在非隔离上下文读取的当前色板（切换主题时同步写入）。
enum ThemePaletteCache {
    nonisolated(unsafe) static var isDark = true
    nonisolated(unsafe) static var palette: DSColorPalette = DSColor.dark
}

/// 当前主题偏好。`auto` 跟随系统；解析后的深/浅写入 ThemePaletteCache。
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    /// 用户选择：深色 / 浅色 / 自动
    private(set) var theme: AppTheme
    /// 实际生效的深浅（auto 时随系统变）；用于 `.id` 强制重绘
    private(set) var resolvedDark: Bool

    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .dark: return .dark
        case .light: return .light
        case .auto: return nil
        }
    }

    private static let storageKey = "app.theme"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let saved = AppTheme(rawValue: raw) {
            theme = saved
        } else {
            theme = .dark
        }
        resolvedDark = Self.systemIsDark()
        syncPaletteCache()
        // 不在 init 里碰 NSApp.appearance；等 AppDelegate。
    }

    func set(_ theme: AppTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey)
        refreshResolved(systemDark: Self.systemIsDark())
        applySystemAppearance()
    }

    /// 深色 → 浅色 → 自动 → 深色
    func cycle() {
        switch theme {
        case .dark: set(.light)
        case .light: set(.auto)
        case .auto: set(.dark)
        }
    }

    /// SwiftUI `colorScheme` 变化时调用（auto 模式跟随系统）。
    func syncFromSystemColorScheme(_ scheme: ColorScheme) {
        guard theme == .auto else { return }
        refreshResolved(systemDark: scheme == .dark)
    }

    /// 由 AppDelegate 在 applicationDidFinishLaunching 调用；切换主题时也会调用。
    func applySystemAppearance() {
        guard NSApp != nil else { return }
        switch theme {
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .auto:
            NSApp.appearance = nil
        }
        refreshResolved(systemDark: Self.systemIsDark())
    }

    private func refreshResolved(systemDark: Bool) {
        let dark: Bool
        switch theme {
        case .dark: dark = true
        case .light: dark = false
        case .auto: dark = systemDark
        }
        resolvedDark = dark
        syncPaletteCache()
    }

    private func syncPaletteCache() {
        ThemePaletteCache.isDark = resolvedDark
        ThemePaletteCache.palette = resolvedDark ? DSColor.dark : DSColor.light
    }

    private static func systemIsDark() -> Bool {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
