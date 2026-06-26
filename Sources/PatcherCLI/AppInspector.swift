// 文件说明：检测目标网易云音乐 App 和当前补丁状态

import Foundation

struct AppInspector {
    private let backupManager = BackupManager()
    private let injector = MachOLoadCommandInjector()

    func inspect(appURL: URL) -> AppStatus {
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: appURL.path)
        let bundle = exists ? Bundle(url: appURL) : nil
        let info = bundle?.infoDictionary ?? [:]
        let bundleIdentifier = info["CFBundleIdentifier"] as? String
        let version = info["CFBundleShortVersionString"] as? String
        let bundleVersion = info["CFBundleVersion"] as? String
        let executableName = info["CFBundleExecutable"] as? String
        let executableURL = executableName.map {
            appURL.appendingPathComponent("Contents/MacOS/\($0)")
        }
        let frameworkURL = appURL.appendingPathComponent("Contents/Frameworks/\(patchDylibFileName)")
        let dylibExists = fileManager.fileExists(atPath: frameworkURL.path)
        let isSupportedVersion = version == supportedAppVersion && bundleVersion == supportedBundleVersion
        let backupURL = backupManager.existingBackup(version: version, bundleVersion: bundleVersion)
        let executableLoadsPatch = loadCommandExists(executableURL: executableURL)
        let isRunning = executableName.map(isProcessRunning(named:)) ?? false
        let signatureMessage = verifySignature(appURL: appURL, exists: exists)

        return AppStatus(
            appURL: appURL,
            exists: exists,
            bundleIdentifier: bundleIdentifier,
            version: version,
            bundleVersion: bundleVersion,
            executableURL: executableURL,
            isRunning: isRunning,
            isSupportedVersion: isSupportedVersion,
            dylibExists: dylibExists,
            executableLoadsPatch: executableLoadsPatch,
            backupURL: backupURL,
            signatureMessage: signatureMessage
        )
    }

    private func loadCommandExists(executableURL: URL?) -> Bool {
        guard let executableURL,
              FileManager.default.fileExists(atPath: executableURL.path) else {
            return false
        }

        return (try? injector.containsDylib(executableURL: executableURL, dylibPath: injectedDylibPath)) ?? false
    }

    private func isProcessRunning(named processName: String) -> Bool {
        guard let result = try? ProcessRunner.run("/usr/bin/pgrep", arguments: ["-x", processName]) else {
            return false
        }

        return result.succeeded
    }

    private func verifySignature(appURL: URL, exists: Bool) -> String {
        guard exists else {
            return "未检测：App 不存在"
        }

        guard let result = try? ProcessRunner.run("/usr/bin/codesign", arguments: ["--verify", "--strict", appURL.path]) else {
            return "无法执行 codesign 验证"
        }

        if result.succeeded {
            return "通过"
        }

        let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "失败" : "失败：\(message)"
    }
}
