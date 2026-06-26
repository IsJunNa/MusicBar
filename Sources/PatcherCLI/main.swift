// 文件说明：补丁工具命令入口

import Foundation

func printHelp() {
    print("""
    用法：
      nmlrc-bg-patcher status [--app /Applications/NeteaseMusic.app]
      nmlrc-bg-patcher apply --mode transparent|solid|gradient [--yes] [--force-version]
      nmlrc-bg-patcher restore [--yes]
      nmlrc-bg-patcher write-config --mode transparent|solid|gradient

    背景参数：
      --gradient-start #111827
      --gradient-end #2563EB
      --direction leftToRight|rightToLeft|topToBottom|bottomToTop|topLeftToBottomRight|topRightToBottomLeft
      --opacity 0.8
      --corner-radius 12
      纯色模式使用 --gradient-start 作为背景颜色

    歌词参数：
      --lyric-color #000000
      --lyric-font-name PingFangSC-Semibold
      --lyric-font-size 23
      --lyric-gradient-enabled true|false
      --lyric-gradient-start #FFFFFF
      --lyric-gradient-end #9FD8FF
      --lyric-gradient-direction leftToRight|rightToLeft|topToBottom|bottomToTop|topLeftToBottomRight|topRightToBottomLeft

    其他参数：
      --app /Applications/NeteaseMusic.app
      --dylib /path/to/NMLyricBackgroundPatch.dylib
      --quit-netease
    """)
}

do {
    let command = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst()))
    let installer = PatchInstaller()

    switch command {
    case .status(let appURL):
        installer.printStatus(appURL: appURL)
    case .apply(let options):
        try installer.apply(options)
    case .restore(let options):
        try installer.restore(options)
    case .writeConfig(let options):
        try installer.writeConfig(options)
    case .help:
        printHelp()
    }
} catch let error as PatchCLIError {
    fputs("错误：\(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("错误：\(error.localizedDescription)\n", stderr)
    exit(1)
}
