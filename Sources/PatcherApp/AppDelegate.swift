// 文件说明：管理 App 生命周期和主窗口展示

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PatcherWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        let controller = PatcherWindowController()
        controller.showWindow(nil)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else {
            return true
        }
        // Dock 图标重新点开时复用原来的主窗口，不重新创建控制器
        windowController?.showMainWindow()
        return true
    }

    /// 创建系统菜单栏入口，关于单独放到顶层菜单，内容复用主窗口里的信息弹窗
    private func configureMainMenu() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MusicBar"
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: appName)
        let aboutMenuItem = NSMenuItem(title: "关于", action: nil, keyEquivalent: "")
        let aboutMenu = NSMenu(title: "关于")
        let logMenuItem = NSMenuItem(title: "日志", action: nil, keyEquivalent: "")
        let logMenu = NSMenu(title: "日志")

        let aboutItem = NSMenuItem(title: "关于 \(appName)", action: #selector(showAppInfoFromMenu), keyEquivalent: "")
        aboutItem.target = self
        aboutMenu.addItem(aboutItem)

        let uploadLogItem = NSMenuItem(title: "上传日志", action: #selector(uploadLogFromMenu), keyEquivalent: "")
        uploadLogItem.target = self
        logMenu.addItem(uploadLogItem)

        appMenu.addItem(NSMenuItem(title: "退出 \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        appMenuItem.submenu = appMenu
        aboutMenuItem.submenu = aboutMenu
        logMenuItem.submenu = logMenu
        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(aboutMenuItem)
        mainMenu.addItem(logMenuItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func showAppInfoFromMenu() {
        windowController?.showAppInfo()
    }

    /// 菜单入口会打开默认邮箱，并把当前机器上的补丁日志带到邮件正文里
    @objc private func uploadLogFromMenu() {
        let logID = makeLogID()
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "MusicBar 日志 \(logID)"),
            URLQueryItem(name: "body", value: makeUploadLogMailBody(logID: logID))
        ]

        guard let url = components.url else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 日志 id 用当前时间生成，便于把用户邮件和排查记录对应起来
    private func makeLogID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }

    /// 这里复用运行时写入日志的固定路径，不额外创建临时文件
    private func patchLogURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NMLyricBackgroundPatch/patch.log")
    }

    /// 邮件正文直接包含本地日志内容，方便用户确认后发送
    private func makeUploadLogMailBody(logID: String) -> String {
        let logURL = patchLogURL()
        let logContent = (try? String(contentsOf: logURL, encoding: .utf8)) ?? "未找到本地日志文件：\(logURL.path)"

        return """
        日志 ID：\(logID)
        系统版本：\(ProcessInfo.processInfo.operatingSystemVersionString)
        日志路径：\(logURL.path)

        日志内容：
        \(logContent)
        """
    }
}
