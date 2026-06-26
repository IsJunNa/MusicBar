// 文件说明：解析 nmlrc-bg-patcher 命令行参数

import Foundation

enum CLIArguments {
    static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let command = arguments.first else {
            return .help
        }

        let parser = OptionParser(arguments: Array(arguments.dropFirst()))
        switch command {
        case "status":
            return .status(appURL: parser.appURL())
        case "apply":
            return .apply(try parser.applyOptions())
        case "restore":
            return .restore(parser.restoreOptions())
        case "write-config":
            return .writeConfig(try parser.writeConfigOptions())
        case "-h", "--help", "help":
            return .help
        default:
            throw PatchCLIError.message("未知命令：\(command)")
        }
    }
}

private struct OptionParser {
    let arguments: [String]

    func appURL() -> URL {
        URL(fileURLWithPath: value(for: "--app") ?? defaultAppPath)
    }

    func applyOptions() throws -> ApplyOptions {
        let mode = try parsedMode()
        return ApplyOptions(
            appURL: appURL(),
            dylibURL: dylibURL(),
            mode: mode,
            blurMaterial: try parsedBlurMaterial(),
            gradientStartColor: value(for: "--gradient-start") ?? "#111827",
            gradientEndColor: value(for: "--gradient-end") ?? "#2563EB",
            gradientDirection: try parsedDirection(),
            cornerRadius: try parsedCornerRadius(),
            opacity: try parsedOpacity(),
            lyricColor: value(for: "--lyric-color"),
            lyricPlayedColor: value(for: "--lyric-played-color"),
            lyricUnplayedColor: value(for: "--lyric-unplayed-color"),
            lyricFontName: value(for: "--lyric-font-name") ?? LyricFontOption.pingFangSemibold.rawValue,
            lyricFontSize: try parsedLyricFontSize(),
            lyricGradientEnabled: parsedLyricGradientEnabled(),
            lyricGradientStartColor: value(for: "--lyric-gradient-start") ?? "#FFFFFF",
            lyricGradientEndColor: value(for: "--lyric-gradient-end") ?? "#9FD8FF",
            lyricGradientDirection: try parsedLyricGradientDirection(),
            yes: hasFlag("--yes"),
            forceVersion: hasFlag("--force-version"),
            quitNetease: hasFlag("--quit-netease")
        )
    }

    func restoreOptions() -> RestoreOptions {
        RestoreOptions(appURL: appURL(), yes: hasFlag("--yes"), quitNetease: hasFlag("--quit-netease"))
    }

    func writeConfigOptions() throws -> WriteConfigOptions {
        WriteConfigOptions(
            appURL: appURL(),
            mode: try parsedMode(),
            blurMaterial: try parsedBlurMaterial(),
            gradientStartColor: value(for: "--gradient-start") ?? "#111827",
            gradientEndColor: value(for: "--gradient-end") ?? "#2563EB",
            gradientDirection: try parsedDirection(),
            cornerRadius: try parsedCornerRadius(),
            opacity: try parsedOpacity(),
            lyricColor: value(for: "--lyric-color"),
            lyricPlayedColor: value(for: "--lyric-played-color"),
            lyricUnplayedColor: value(for: "--lyric-unplayed-color"),
            lyricFontName: value(for: "--lyric-font-name") ?? LyricFontOption.pingFangSemibold.rawValue,
            lyricFontSize: try parsedLyricFontSize(),
            lyricGradientEnabled: parsedLyricGradientEnabled(),
            lyricGradientStartColor: value(for: "--lyric-gradient-start") ?? "#FFFFFF",
            lyricGradientEndColor: value(for: "--lyric-gradient-end") ?? "#9FD8FF",
            lyricGradientDirection: try parsedLyricGradientDirection()
        )
    }

    // 默认从 CLI 所在目录读取 dylib，方便 dist 目录直接分发
    private func dylibURL() -> URL {
        if let path = value(for: "--dylib") {
            return URL(fileURLWithPath: path)
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        return executableURL.deletingLastPathComponent().appendingPathComponent(patchDylibFileName)
    }

    private func parsedMode() throws -> PatchMode {
        guard let rawMode = value(for: "--mode") else {
            throw PatchCLIError.message("缺少 --mode，可选值：transparent、solid、gradient")
        }
        guard let mode = PatchMode.value(from: rawMode) else {
            throw PatchCLIError.message("不支持的模式：\(rawMode)")
        }

        return mode
    }

    private func parsedBlurMaterial() throws -> BlurMaterial {
        let rawMaterial = value(for: "--blur-material") ?? BlurMaterial.ultraThin.rawValue
        guard let material = BlurMaterial(rawValue: rawMaterial) else {
            throw PatchCLIError.message("不支持的旧背景材质参数：\(rawMaterial)")
        }

        return material
    }

    private func parsedDirection() throws -> GradientDirection {
        let rawDirection = value(for: "--direction") ?? GradientDirection.leftToRight.rawValue
        guard let direction = GradientDirection.value(from: rawDirection) else {
            throw PatchCLIError.message("不支持的渐变方向：\(rawDirection)")
        }

        return direction
    }

    private func parsedOpacity() throws -> Double {
        let rawOpacity = value(for: "--opacity") ?? "0.8"
        guard let opacity = Double(rawOpacity), opacity >= 0, opacity <= 1 else {
            throw PatchCLIError.message("--opacity 必须是 0 到 1 之间的数字")
        }

        return opacity
    }

    private func parsedLyricFontSize() throws -> Double {
        let rawSize = value(for: "--lyric-font-size") ?? "23"
        guard let fontSize = Double(rawSize), fontSize >= 12, fontSize <= 72 else {
            throw PatchCLIError.message("--lyric-font-size 必须是 12 到 72 之间的数字")
        }

        return fontSize
    }

    private func parsedLyricGradientEnabled() -> Bool {
        let rawValue = value(for: "--lyric-gradient-enabled")
        return rawValue == "true" || rawValue == "1" || hasFlag("--lyric-gradient")
    }

    private func parsedLyricGradientDirection() throws -> GradientDirection {
        let rawDirection = value(for: "--lyric-gradient-direction") ?? GradientDirection.leftToRight.rawValue
        guard let direction = GradientDirection.value(from: rawDirection) else {
            throw PatchCLIError.message("不支持的歌词渐变方向：\(rawDirection)")
        }

        return direction
    }

    private func parsedCornerRadius() throws -> Double {
        let rawRadius = value(for: "--corner-radius") ?? "8"
        guard let radius = Double(rawRadius), radius >= 0, radius <= 48 else {
            throw PatchCLIError.message("--corner-radius 必须是 0 到 48 之间的数字")
        }

        return radius
    }

    private func value(for option: String) -> String? {
        guard let index = arguments.firstIndex(of: option) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }

        return arguments[valueIndex]
    }

    private func hasFlag(_ flag: String) -> Bool {
        arguments.contains(flag)
    }
}
