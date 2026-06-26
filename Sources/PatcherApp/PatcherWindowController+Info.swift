// 文件说明：原生补丁工具应用信息弹窗

import AppKit

extension PatcherWindowController {
    /// 展示应用图标、版本和外部入口
    func presentAppInfo() {
        let alert = NSAlert()
        alert.messageText = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MusicBar"
        alert.informativeText = appInfoText()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开 GitHub")
        alert.addButton(withTitle: "反馈")
        alert.addButton(withTitle: "好")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openGithub()
        case .alertSecondButtonReturn:
            openFeedbackMail()
        default:
            break
        }
    }

    /// 组装版本、作者和 GitHub 求星提示，优先读取 Info.plist 中的正式版本号
    private func appInfoText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? patchToolVersion
        return """
        版本 \(version)
        作者：Jump

        喜欢的话，欢迎在 GitHub 给项目点个 Star 🌟
        """
    }

    private func openGithub() {
        guard let url = URL(string: projectGithubURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 使用 mailto 预填反馈模板，具体能否带正文取决于用户默认邮件客户端
    private func openFeedbackMail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "MusicBar 反馈"),
            URLQueryItem(name: "body", value: feedbackTemplate())
        ]

        guard let url = components.url else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func feedbackTemplate() -> String {
        """
        反馈类型：Bug / 功能建议

        现象或想要的功能：


        复现步骤：
        1.
        2.
        3.

        期望结果：


        系统版本：\(ProcessInfo.processInfo.operatingSystemVersionString)
        App 版本：\(appInfoText())
        """
    }
}
