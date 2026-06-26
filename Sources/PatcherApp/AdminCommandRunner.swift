// 文件说明：通过系统管理员授权执行内置补丁命令

import Foundation

enum AdminCommandRunnerError: Error {
    case userCancelled
}

struct AdminCommandRunner {
    func run(executablePath: String, arguments: [String]) throws -> String {
        let shellCommand = userEnvironmentPrefix() + ShellEscaper.command(executablePath: executablePath, arguments: arguments)
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MusicBar"
        // 在 App 进程内发起管理员授权，避免系统弹窗把请求方显示成 osascript
        let script = """
        do shell script \(appleScriptString(shellCommand)) with administrator privileges with prompt \(appleScriptString("\(appName) 需要授权密码来修改网易云音乐配置文件并应用更改"))
        """

        var errorInfo: NSDictionary?
        guard let output = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo) else {
            if isUserCancelled(errorInfo) {
                throw AdminCommandRunnerError.userCancelled
            }
            throw PatchCLIError.message(appleScriptErrorMessage(errorInfo))
        }

        return output.stringValue ?? ""
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func appleScriptErrorMessage(_ errorInfo: NSDictionary?) -> String {
        guard let message = errorInfo?[NSAppleScript.errorMessage] as? String,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "管理员授权失败"
        }

        return message
    }

    private func isUserCancelled(_ errorInfo: NSDictionary?) -> Bool {
        // AppleScript 在用户取消管理员授权时固定返回 -128，用它区分主动取消和真实执行失败
        if let errorNumber = errorInfo?[NSAppleScript.errorNumber] as? NSNumber,
           errorNumber.intValue == -128 {
            return true
        }

        let message = (errorInfo?[NSAppleScript.errorMessage] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message == "用户已取消。" || message == "User canceled."
    }

    private func userEnvironmentPrefix() -> String {
        let userName = NSUserName()
        let groupResult = ProcessRunner.runQuietly("/usr/bin/id", arguments: ["-g", userName])
        let groupID = groupResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeGroupID = groupID.isEmpty ? "20" : groupID

        // 管理员授权后进程以 root 执行，显式传原用户，避免配置写进 /var/root
        return "SUDO_USER=\(ShellEscaper.quote(userName)) SUDO_GID=\(ShellEscaper.quote(safeGroupID)) "
    }
}
