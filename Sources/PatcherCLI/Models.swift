// 文件说明：补丁工具共享模型和固定配置

import Foundation

let patchToolVersion = "0.1.1"
let supportedAppVersion = "3.1.9"
let supportedBundleVersion = "3364"
let defaultAppPath = "/Applications/NeteaseMusic.app"
let patchDylibFileName = "NMLyricBackgroundPatch.dylib"
let patchConfigFileName = "NMLyricBackgroundPatchConfig.json"
let injectedDylibPath = "@executable_path/../Frameworks/NMLyricBackgroundPatch.dylib"

// sudo 应用补丁时仍要把备份和历史配置写到原登录用户目录
let patchUserHomeURL: URL = {
    let environment = ProcessInfo.processInfo.environment
    if let sudoUser = environment["SUDO_USER"],
       !sudoUser.isEmpty,
       sudoUser != "root",
       let homePath = NSHomeDirectoryForUser(sudoUser) {
        return URL(fileURLWithPath: homePath, isDirectory: true)
    }

    return FileManager.default.homeDirectoryForCurrentUser
}()

let supportRootURL = patchUserHomeURL
    .appendingPathComponent("Library/Application Support/NMLyricBackgroundPatch", isDirectory: true)
let configURL = supportRootURL.appendingPathComponent("config.json")
let backupsRootURL = supportRootURL.appendingPathComponent("Backups", isDirectory: true)
let projectGithubURL = "https://github.com/IsJunNa/MusicBar"
let feedbackEmailAddress = "zhujump@linux.do"

// 运行时优先读取 App Bundle 内的配置，避免访问网易云容器外的数据目录
func bundleConfigURL(appURL: URL) -> URL {
    appURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent(patchConfigFileName)
}

enum PatchCLIError: Error, CustomStringConvertible, LocalizedError {
    case message(String)

    var description: String {
        switch self {
        case .message(let value):
            return value
        }
    }

    var errorDescription: String? {
        description
    }
}

enum PatchMode: String, Codable, CaseIterable {
    case transparent
    case solid
    case gradient

    /// 读取历史配置时把旧 blur 模式迁移到纯色背景
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let mode = PatchMode.value(from: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "不支持的背景模式：\(rawValue)"
            )
        }

        self = mode
    }

    /// 写配置时只输出当前支持的模式名
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// CLI 仍接受旧 blur 参数，方便老脚本继续运行
    static func value(from rawValue: String) -> PatchMode? {
        if rawValue == "blur" {
            return .solid
        }

        return PatchMode(rawValue: rawValue)
    }

    var displayName: String {
        switch self {
        case .transparent:
            return "透明"
        case .solid:
            return "纯色"
        case .gradient:
            return "渐变"
        }
    }
}

/// 旧 blur 参数保留读取能力，避免历史配置和脚本解析失败
enum BlurMaterial: String, Codable, CaseIterable {
    case ultraThin
    case thin
    case regular
    case sidebar
    case hudWindow

    var displayName: String {
        switch self {
        case .ultraThin:
            return "Ultra Thin"
        case .thin:
            return "Thin"
        case .regular:
            return "Regular"
        case .sidebar:
            return "Sidebar"
        case .hudWindow:
            return "HUD"
        }
    }
}

/// 渐变方向选项对应 UI 下拉项，保留旧 diagonal 配置的读取兼容
enum GradientDirection: String, Codable, CaseIterable {
    case leftToRight
    case rightToLeft
    case topToBottom
    case bottomToTop
    case topLeftToBottomRight
    case topRightToBottomLeft

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let direction = GradientDirection.value(from: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "不支持的渐变方向：\(rawValue)"
            )
        }

        self = direction
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func value(from rawValue: String) -> GradientDirection? {
        if rawValue == "diagonal" {
            return .topLeftToBottomRight
        }

        return GradientDirection(rawValue: rawValue)
    }

    var displayName: String {
        switch self {
        case .leftToRight:
            return "从左到右"
        case .rightToLeft:
            return "从右到左"
        case .topToBottom:
            return "从上到下"
        case .bottomToTop:
            return "从下到上"
        case .topLeftToBottomRight:
            return "左上 → 右下"
        case .topRightToBottomLeft:
            return "右上 → 左下"
        }
    }
}

/// 歌词字体选项使用常见 macOS 字体，保存的是 NSFont 可识别的字体名
enum LyricFontOption: String, Codable, CaseIterable {
    case pingFangSemibold = "PingFangSC-Semibold"
    case pingFangMedium = "PingFangSC-Medium"
    case pingFangRegular = "PingFangSC-Regular"
    case pingFangLight = "PingFangSC-Light"
    case hiraginoSans = "HiraginoSans-W6"
    case hiraginoSansRegular = "HiraginoSans-W3"
    case hiraginoSansGB = "HiraginoSansGB-W6"
    case heiti = "STHeitiSC-Medium"
    case songti = "STSongti-SC-Regular"
    case songtiBold = "STSongti-SC-Bold"
    case helveticaNeue = "HelveticaNeue-Medium"
    case avenirNext = "AvenirNext-Medium"
    case menlo = "Menlo-Regular"
    case timesNewRoman = "TimesNewRomanPSMT"

    var displayName: String {
        switch self {
        case .pingFangSemibold:
            return "苹方 半粗"
        case .pingFangMedium:
            return "苹方 中黑"
        case .pingFangRegular:
            return "苹方 常规"
        case .pingFangLight:
            return "苹方 细体"
        case .hiraginoSans:
            return "冬青黑体 粗"
        case .hiraginoSansRegular:
            return "冬青黑体 常规"
        case .hiraginoSansGB:
            return "冬青简体 粗"
        case .heiti:
            return "黑体"
        case .songti:
            return "宋体"
        case .songtiBold:
            return "宋体 粗"
        case .helveticaNeue:
            return "Helvetica"
        case .avenirNext:
            return "Avenir Next"
        case .menlo:
            return "Menlo"
        case .timesNewRoman:
            return "Times New Roman"
        }
    }
}

struct PatchConfig: Codable {
    let patchVersion: String
    let targetBundleVersion: String
    let mode: PatchMode
    let blurMaterial: BlurMaterial
    let cornerRadius: Double
    let gradientStartColor: String
    let gradientEndColor: String
    let gradientDirection: GradientDirection
    let opacity: Double
    /// 当前使用的歌词单色，旧版本未写入时会用 lyricPlayedColor 兼容
    let lyricColor: String?
    /// 旧版本的已播放歌词颜色字段，仅用于读取历史配置和兼容旧 CLI 参数
    let lyricPlayedColor: String?
    /// 旧版本的未播放歌词颜色字段，仅用于读取历史配置和兼容旧 CLI 参数
    let lyricUnplayedColor: String?
    let lyricFontName: String?
    let lyricFontSize: Double?
    let lyricGradientEnabled: Bool?
    let lyricGradientStartColor: String?
    let lyricGradientEndColor: String?
    let lyricGradientDirection: GradientDirection?

    // 统一生成运行时读取的配置，避免 CLI 和 dylib 默认值分叉
    static func make(
        targetBundleVersion: String,
        mode: PatchMode,
        blurMaterial: BlurMaterial,
        cornerRadius: Double,
        gradientStartColor: String,
        gradientEndColor: String,
        gradientDirection: GradientDirection,
        opacity: Double,
        lyricColor: String?,
        lyricPlayedColor: String?,
        lyricUnplayedColor: String?,
        lyricFontName: String,
        lyricFontSize: Double,
        lyricGradientEnabled: Bool,
        lyricGradientStartColor: String,
        lyricGradientEndColor: String,
        lyricGradientDirection: GradientDirection
    ) -> PatchConfig {
        PatchConfig(
            patchVersion: patchToolVersion,
            targetBundleVersion: targetBundleVersion,
            mode: mode,
            blurMaterial: blurMaterial,
            cornerRadius: cornerRadius,
            gradientStartColor: gradientStartColor,
            gradientEndColor: gradientEndColor,
            gradientDirection: gradientDirection,
            opacity: opacity,
            lyricColor: lyricColor,
            lyricPlayedColor: lyricPlayedColor,
            lyricUnplayedColor: lyricUnplayedColor,
            lyricFontName: lyricFontName,
            lyricFontSize: lyricFontSize,
            lyricGradientEnabled: lyricGradientEnabled,
            lyricGradientStartColor: lyricGradientStartColor,
            lyricGradientEndColor: lyricGradientEndColor,
            lyricGradientDirection: lyricGradientDirection
        )
    }
}

struct AppStatus {
    let appURL: URL
    let exists: Bool
    let bundleIdentifier: String?
    let version: String?
    let bundleVersion: String?
    let executableURL: URL?
    let isRunning: Bool
    let isSupportedVersion: Bool
    let dylibExists: Bool
    let executableLoadsPatch: Bool
    let backupURL: URL?
    let signatureMessage: String
}

struct ApplyOptions {
    let appURL: URL
    let dylibURL: URL
    let mode: PatchMode
    let blurMaterial: BlurMaterial
    let gradientStartColor: String
    let gradientEndColor: String
    let gradientDirection: GradientDirection
    let cornerRadius: Double
    let opacity: Double
    let lyricColor: String?
    let lyricPlayedColor: String?
    let lyricUnplayedColor: String?
    let lyricFontName: String
    let lyricFontSize: Double
    let lyricGradientEnabled: Bool
    let lyricGradientStartColor: String
    let lyricGradientEndColor: String
    let lyricGradientDirection: GradientDirection
    let yes: Bool
    let forceVersion: Bool
    let quitNetease: Bool
}

struct RestoreOptions {
    let appURL: URL
    let yes: Bool
    let quitNetease: Bool
}

struct WriteConfigOptions {
    let appURL: URL
    let mode: PatchMode
    let blurMaterial: BlurMaterial
    let gradientStartColor: String
    let gradientEndColor: String
    let gradientDirection: GradientDirection
    let cornerRadius: Double
    let opacity: Double
    let lyricColor: String?
    let lyricPlayedColor: String?
    let lyricUnplayedColor: String?
    let lyricFontName: String
    let lyricFontSize: Double
    let lyricGradientEnabled: Bool
    let lyricGradientStartColor: String
    let lyricGradientEndColor: String
    let lyricGradientDirection: GradientDirection
}

enum CLICommand {
    case status(appURL: URL)
    case apply(ApplyOptions)
    case restore(RestoreOptions)
    case writeConfig(WriteConfigOptions)
    case help
}
