// 文件说明：转换 NSColor 和补丁配置使用的十六进制颜色

import AppKit

enum HexColor {
    static func color(from hex: String, fallback: NSColor) -> NSColor {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        guard value.count == 6,
              let number = Int(value, radix: 16) else {
            return fallback
        }

        let red = CGFloat((number >> 16) & 0xff) / 255
        let green = CGFloat((number >> 8) & 0xff) / 255
        let blue = CGFloat(number & 0xff) / 255
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }

    static func hex(from color: NSColor) -> String {
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        let red = Int(round(rgbColor.redComponent * 255))
        let green = Int(round(rgbColor.greenComponent * 255))
        let blue = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
