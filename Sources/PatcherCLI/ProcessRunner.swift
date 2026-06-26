// 文件说明：封装系统命令调用和输出收集

import Foundation

struct ProcessResult {
    let exitCode: Int32
    let output: String

    var succeeded: Bool {
        exitCode == 0
    }
}

enum ProcessRunner {
    // 用于调用 codesign、pgrep、ditto 等 macOS 系统工具
    static func run(_ executablePath: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, output: output)
    }

    static func runQuietly(_ executablePath: String, arguments: [String]) -> ProcessResult {
        (try? run(executablePath, arguments: arguments)) ?? ProcessResult(exitCode: 1, output: "")
    }
}
