// 文件说明：管理网易云音乐 App 本体备份和恢复

import Foundation

struct BackupManager {
    private let fileManager = FileManager.default

    func backupURL(version: String?, bundleVersion: String?) -> URL? {
        guard let version, let bundleVersion else {
            return nil
        }

        let name = "NeteaseMusic-\(version)-\(bundleVersion).app"
        return backupsRootURL.appendingPathComponent(name, isDirectory: true)
    }

    func existingBackup(version: String?, bundleVersion: String?) -> URL? {
        guard let url = backupURL(version: version, bundleVersion: bundleVersion),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return url
    }

    // 首次应用补丁前复制完整 App，保留签名相关元数据
    func ensureBackup(appURL: URL, version: String?, bundleVersion: String?) throws -> URL {
        guard let backupURL = backupURL(version: version, bundleVersion: bundleVersion) else {
            throw PatchCLIError.message("无法确定备份路径：缺少版本信息")
        }

        if fileManager.fileExists(atPath: backupURL.path) {
            return backupURL
        }

        try fileManager.createDirectory(at: backupsRootURL, withIntermediateDirectories: true)
        let result = try ProcessRunner.run("/usr/bin/ditto", arguments: [appURL.path, backupURL.path])
        guard result.succeeded else {
            throw PatchCLIError.message("备份失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        return backupURL
    }

    // 先复制到临时目录，再整体替换 App，避免逐文件覆盖被系统权限拦截
    func restore(appURL: URL, backupURL: URL) throws {
        let stagingRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NMLyricBackgroundPatchRestore-\(UUID().uuidString)", isDirectory: true)
        let stagingURL = stagingRootURL.appendingPathComponent(appURL.lastPathComponent, isDirectory: true)

        defer {
            try? fileManager.removeItem(at: stagingRootURL)
        }

        try fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)

        let copyResult = try ProcessRunner.run("/usr/bin/ditto", arguments: [backupURL.path, stagingURL.path])
        guard copyResult.succeeded else {
            throw PatchCLIError.message("复制备份失败：\(copyResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        try replaceApp(appURL: appURL, with: stagingURL, label: "restore")
    }

    func replaceApp(appURL: URL, with stagedAppURL: URL, label: String) throws {
        let parentURL = appURL.deletingLastPathComponent()
        let parkedURL = uniqueSiblingURL(parentURL: parentURL, baseName: "\(appURL.lastPathComponent).\(label)-previous")

        if fileManager.fileExists(atPath: appURL.path) {
            try fileManager.moveItem(at: appURL, to: parkedURL)
        }

        do {
            try fileManager.moveItem(at: stagedAppURL, to: appURL)
            try? fileManager.removeItem(at: parkedURL)
        } catch {
            if fileManager.fileExists(atPath: parkedURL.path),
               !fileManager.fileExists(atPath: appURL.path) {
                try? fileManager.moveItem(at: parkedURL, to: appURL)
            }
            throw error
        }
    }

    private func uniqueSiblingURL(parentURL: URL, baseName: String) -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        var candidate = parentURL.appendingPathComponent("\(baseName)-\(timestamp)", isDirectory: true)
        var index = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parentURL.appendingPathComponent("\(baseName)-\(timestamp)-\(index)", isDirectory: true)
            index += 1
        }

        return candidate
    }
}
