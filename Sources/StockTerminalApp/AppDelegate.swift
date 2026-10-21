import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // swift run 启动的裸可执行文件默认不进前台、Dock 无图标——修正激活策略
        NSApp.setActivationPolicy(.regular)
        // 跟随 ThemeStore（深色 / 浅色），不要写死 darkAqua
        ThemeStore.shared.applySystemAppearance()
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
