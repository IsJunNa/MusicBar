// 文件说明：修正 sudo 写入后配置目录的归属用户

import Foundation

enum SupportDirectoryOwner {
    // sudo apply 会以 root 写入用户目录，这里把配置和备份目录还给原登录用户
    static func restoreIfNeeded() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sudoUser = environment["SUDO_USER"],
              !sudoUser.isEmpty,
              sudoUser != "root" else {
            return
        }

        let group = environment["SUDO_GID"] ?? "20"
        guard FileManager.default.fileExists(atPath: supportRootURL.path) else {
            return
        }

        let result = try ProcessRunner.run("/usr/sbin/chown", arguments: ["-R", "\(sudoUser):\(group)", supportRootURL.path])
        guard result.succeeded else {
            throw PatchCLIError.message("修正配置目录权限失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
