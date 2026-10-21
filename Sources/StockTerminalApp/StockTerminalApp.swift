import SwiftUI

@main
struct StockTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment.live()
    @State private var theme = ThemeStore.shared

    var body: some Scene {
        WindowGroup("量化终端") {
            ContentView()
                .environment(env)
                .environment(theme)
                .preferredColorScheme(theme.theme.colorScheme)
                // 切换主题时强制整树按新色板重绘（含 Canvas）
                .id(theme.theme)
                // 右栏最矮：工具栏 52 + 五档 252 + 逐笔 84 + 下单约 300 + 间距，约 740。
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1480, height: 920)
    }
}
