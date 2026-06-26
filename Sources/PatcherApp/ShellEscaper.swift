// 文件说明：为管理员授权命令生成安全 shell 参数

import Foundation

enum ShellEscaper {
    // AppleScript 的 do shell script 只接收字符串命令，参数必须逐个转义
    static func quote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func command(executablePath: String, arguments: [String]) -> String {
        ([quote(executablePath)] + arguments.map(quote)).joined(separator: " ")
    }
}
