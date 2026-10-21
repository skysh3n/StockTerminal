import SwiftUI

@main
struct StockTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment.live()
    @State private var theme = ThemeStore.shared

    var body: some Scene {
        WindowGroup("量化终端") {
            ThemeRoot(theme: theme) {
                ContentView()
                    .environment(env)
                    .environment(theme)
                    // 右栏最矮：工具栏 52 + 五档 252 + 逐笔 84 + 下单约 300 + 间距，约 740。
                    .frame(minWidth: 1180, minHeight: 760)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1480, height: 920)
    }
}

/// 包一层以读取系统 `colorScheme`，auto 模式下同步色板。
private struct ThemeRoot<Content: View>: View {
    @Bindable var theme: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .preferredColorScheme(theme.preferredColorScheme)
            .id("\(theme.theme.rawValue)-\(theme.resolvedDark)")
            .onAppear { theme.syncFromSystemColorScheme(colorScheme) }
            .onChange(of: colorScheme) { _, new in
                theme.syncFromSystemColorScheme(new)
            }
    }
}
