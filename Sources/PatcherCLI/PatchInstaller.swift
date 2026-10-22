// 文件说明：实现应用补丁、恢复原版和写配置流程

import Foundation

struct PatchInstaller {
    private let inspector = AppInspector()
    private let backupManager = BackupManager()
    private let configStore = ConfigStore()
    private let injector = MachOLoadCommandInjector()

    func printStatus(appURL: URL) {
        let status = inspector.inspect(appURL: appURL)
        print("App 路径：\(status.appURL.path)")
        print("App 存在：\(status.exists ? "是" : "否")")
        print("Bundle ID：\(status.bundleIdentifier ?? "-")")
        print("版本：\(status.version ?? "-")")
        print("Build：\(status.bundleVersion ?? "-")")
        print("支持版本：\(status.isSupportedVersion ? "是" : "否")")
        print("运行中：\(status.isRunning ? "是" : "否")")
        print("补丁 dylib：\(status.dylibExists ? "已复制" : "未复制")")
        print("加载命令：\(status.executableLoadsPatch ? "已写入" : "未写入")")
        print("备份：\(status.backupURL?.path ?? "无")")
        print("签名：\(status.signatureMessage)")

        if let config = try? configStore.read(appURL: appURL) {
            print("配置模式：\(config.mode.rawValue)（\(config.mode.displayName)）")
            print("配置路径：\(bundleConfigURL(appURL: appURL).path)")
        } else {
            print("配置模式：未写入")
        }
    }

    func writeConfig(_ options: WriteConfigOptions) throws {
        let status = inspector.inspect(appURL: options.appURL)
        let targetBuild = status.bundleVersion ?? supportedBundleVersion
        let config = makeConfig(targetBundleVersion: targetBuild, options: options)
        try configStore.write(config, toApp: options.appURL)
        try SupportDirectoryOwner.restoreIfNeeded()
        print("配置已写入：\(bundleConfigURL(appURL: options.appURL).path)")
    }

    func apply(_ options: ApplyOptions) throws {
        let status = inspector.inspect(appURL: options.appURL)
        try validateApplyPreconditions(status: status, options: options)
        try confirmApplyIfNeeded(options: options, status: status)

        // 先确认版本和资源可用，避免应用失败前就把用户的网易云退出
        if options.quitNetease {
            try quitNeteaseIfNeeded()
        }

        print("创建或复用备份")
        let backupURL = try backupManager.ensureBackup(appURL: options.appURL, version: status.version, bundleVersion: status.bundleVersion)
        print("备份路径：\(backupURL.path)")

        let stagingRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NMLyricBackgroundPatchApply-\(UUID().uuidString)", isDirectory: true)
        let stagingAppURL = stagingRootURL.appendingPathComponent(options.appURL.lastPathComponent, isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: stagingRootURL)
        }

        do {
            try FileManager.default.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)

            print("复制 App 到临时目录")
            let stageCopy = try ProcessRunner.run("/usr/bin/ditto", arguments: [backupURL.path, stagingAppURL.path])
            guard stageCopy.succeeded else {
                throw PatchCLIError.message("复制临时 App 失败：\(stageCopy.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            print("写入补丁 dylib")
            try copyRuntimeDylib(from: options.dylibURL, toApp: stagingAppURL)

            let stagedStatus = inspector.inspect(appURL: stagingAppURL)
            guard let executableURL = stagedStatus.executableURL else {
                throw PatchCLIError.message("无法定位主可执行文件")
            }

            print("写入加载命令")
            let injection = try injector.injectDylib(executableURL: executableURL, dylibPath: injectedDylibPath)
            if injection.patchedSlices == 0 {
                print("加载命令已存在，跳过写入")
            } else {
                print("已写入 \(injection.patchedSlices) 个 Mach-O slice")
            }

            let config = makeConfig(targetBundleVersion: status.bundleVersion ?? supportedBundleVersion, options: options)
            try configStore.write(config, toApp: stagingAppURL)
            try SupportDirectoryOwner.restoreIfNeeded()
            print("配置已写入：\(bundleConfigURL(appURL: stagingAppURL).path)")

            print("签名临时 App")
            try resignPatchedApp(appURL: stagingAppURL)

            print("替换网易云音乐")
            try backupManager.replaceApp(appURL: options.appURL, with: stagingAppURL, label: "apply")
            print("补丁应用完成")
        } catch {
            try? configStore.remove()
            throw error
        }
    }

    func restore(_ options: RestoreOptions) throws {
        if options.quitNetease {
            try quitNeteaseIfNeeded()
        }

        let status = inspector.inspect(appURL: options.appURL)
        guard status.exists else {
            throw PatchCLIError.message("目标 App 不存在：\(options.appURL.path)")
        }
        guard !status.isRunning else {
            throw PatchCLIError.message("网易云音乐正在运行，请先退出后恢复")
        }
        guard let backupURL = status.backupURL else {
            throw PatchCLIError.message("没有找到当前版本对应的备份")
        }

        try confirmRestoreIfNeeded(options: options, status: status, backupURL: backupURL)

        print("恢复备份")
        try backupManager.restore(appURL: options.appURL, backupURL: backupURL)
        try configStore.remove()
        print("配置已删除：\(configURL.path)")

        print("验证恢复后签名")
        let verifyResult = try ProcessRunner.run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", options.appURL.path])
        guard verifyResult.succeeded else {
            throw PatchCLIError.message("恢复完成但签名验证失败：\(verifyResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        print("恢复完成")
    }

    private func validateApplyPreconditions(status: AppStatus, options: ApplyOptions) throws {
        guard status.exists else {
            throw PatchCLIError.message("目标 App 不存在：\(options.appURL.path)")
        }
        guard FileManager.default.fileExists(atPath: options.dylibURL.path) else {
            throw PatchCLIError.message("补丁 dylib 不存在：\(options.dylibURL.path)")
        }
        guard status.bundleIdentifier == "com.netease.163music" else {
            throw PatchCLIError.message("目标 App 不是网易云音乐：\(status.bundleIdentifier ?? "-")")
        }
        guard !status.isRunning || options.quitNetease else {
            throw PatchCLIError.message("网易云音乐正在运行，请先退出后应用补丁")
        }
        guard options.forceVersion || status.isSupportedVersion else {
            throw PatchCLIError.message("当前网易云音乐 \(status.version ?? "-")（build \(status.bundleVersion ?? "-")）尚未适配，请更新 MusicBar 后重试")
        }
    }

    private func quitNeteaseIfNeeded() throws {
        let runningBeforeQuit = ProcessRunner.runQuietly("/usr/bin/pgrep", arguments: ["-x", "NeteaseMusic"]).succeeded
        guard runningBeforeQuit else {
            return
        }

        print("正在退出网易云音乐")
        _ = try? ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", "tell application id \"com.netease.163music\" to quit"])

        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.5)
            let result = ProcessRunner.runQuietly("/usr/bin/pgrep", arguments: ["-x", "NeteaseMusic"])
            if !result.succeeded {
                return
            }
        }

        _ = try? ProcessRunner.run("/usr/bin/pkill", arguments: ["-x", "NeteaseMusic"])
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.5)
            let result = ProcessRunner.runQuietly("/usr/bin/pgrep", arguments: ["-x", "NeteaseMusic"])
            if !result.succeeded {
                return
            }
        }

        throw PatchCLIError.message("无法自动退出网易云音乐，请确认没有系统弹窗阻止退出")
    }

    private func copyRuntimeDylib(from dylibURL: URL, toApp appURL: URL) throws {
        let frameworksURL = appURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let targetURL = frameworksURL.appendingPathComponent(patchDylibFileName)

        try FileManager.default.createDirectory(at: frameworksURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        let result = try ProcessRunner.run("/usr/bin/ditto", arguments: [dylibURL.path, targetURL.path])
        guard result.succeeded else {
            throw PatchCLIError.message("复制补丁 dylib 失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private func resignPatchedApp(appURL: URL) throws {
        try signBundleCodeWithoutEntitlements(appURL: appURL)
        try signMainApp(appURL: appURL)
    }

    private func signBundleCodeWithoutEntitlements(appURL: URL) throws {
        let result = try ProcessRunner.run("/usr/bin/codesign", arguments: ["--force", "--deep", "--sign", "-", appURL.path])
        guard result.succeeded else {
            throw PatchCLIError.message("内嵌代码签名失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private func signMainApp(appURL: URL) throws {
        let entitlementsURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NMLyricBackgroundPatchEntitlements-\(UUID().uuidString).plist")

        defer {
            try? FileManager.default.removeItem(at: entitlementsURL)
        }

        try signingEntitlementsPlist.write(to: entitlementsURL, atomically: true, encoding: .utf8)

        let result = try ProcessRunner.run(
            "/usr/bin/codesign",
            arguments: [
                "--force",
                "--sign",
                "-",
                "--identifier",
                "com.netease.163music",
                "--options",
                "runtime",
                "--generate-entitlement-der",
                "--entitlements",
                entitlementsURL.path,
                appURL.path
            ]
        )
        guard result.succeeded else {
            throw PatchCLIError.message("重签名失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let verify = try ProcessRunner.run("/usr/bin/codesign", arguments: ["--verify", "--strict", appURL.path])
        guard verify.succeeded else {
            throw PatchCLIError.message("重签名后验证失败：\(verify.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    // 只放宽库校验，网易云的 CEF 初始化不兼容 ad-hoc 重签后的 App Sandbox
    private var signingEntitlementsPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.security.cs.disable-library-validation</key>
            <true/>
        </dict>
        </plist>
        """
    }

    private func makeConfig(targetBundleVersion: String, options: ApplyOptions) -> PatchConfig {
        PatchConfig.make(
            targetBundleVersion: targetBundleVersion,
            mode: options.mode,
            blurMaterial: options.blurMaterial,
            cornerRadius: options.cornerRadius,
            gradientStartColor: options.gradientStartColor,
            gradientEndColor: options.gradientEndColor,
            gradientDirection: options.gradientDirection,
            opacity: options.opacity,
            lyricColor: options.lyricColor,
            lyricPlayedColor: options.lyricPlayedColor,
            lyricUnplayedColor: options.lyricUnplayedColor,
            lyricFontName: options.lyricFontName,
            lyricFontSize: options.lyricFontSize,
            lyricGradientEnabled: options.lyricGradientEnabled,
            lyricGradientStartColor: options.lyricGradientStartColor,
            lyricGradientEndColor: options.lyricGradientEndColor,
            lyricGradientDirection: options.lyricGradientDirection
        )
    }

    private func makeConfig(targetBundleVersion: String, options: WriteConfigOptions) -> PatchConfig {
        PatchConfig.make(
            targetBundleVersion: targetBundleVersion,
            mode: options.mode,
            blurMaterial: options.blurMaterial,
            cornerRadius: options.cornerRadius,
            gradientStartColor: options.gradientStartColor,
            gradientEndColor: options.gradientEndColor,
            gradientDirection: options.gradientDirection,
            opacity: options.opacity,
            lyricColor: options.lyricColor,
            lyricPlayedColor: options.lyricPlayedColor,
            lyricUnplayedColor: options.lyricUnplayedColor,
            lyricFontName: options.lyricFontName,
            lyricFontSize: options.lyricFontSize,
            lyricGradientEnabled: options.lyricGradientEnabled,
            lyricGradientStartColor: options.lyricGradientStartColor,
            lyricGradientEndColor: options.lyricGradientEndColor,
            lyricGradientDirection: options.lyricGradientDirection
        )
    }

    private func confirmApplyIfNeeded(options: ApplyOptions, status: AppStatus) throws {
        guard !options.yes else {
            return
        }

        print("将修改并重签名：\(status.appURL.path)")
        print("输入 APPLY 继续：", terminator: "")
        guard readLine() == "APPLY" else {
            throw PatchCLIError.message("已取消")
        }
    }

    private func confirmRestoreIfNeeded(options: RestoreOptions, status: AppStatus, backupURL: URL) throws {
        guard !options.yes else {
            return
        }

        print("将用备份覆盖当前 App：\(status.appURL.path)")
        print("备份路径：\(backupURL.path)")
        print("输入 RESTORE 继续：", terminator: "")
        guard readLine() == "RESTORE" else {
            throw PatchCLIError.message("已取消")
        }
    }
}
