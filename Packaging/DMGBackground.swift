// 文件说明：生成 MusicBar 安装镜像背景图

import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "dist/MusicBar-dmg-background.png"
let canvasSize = NSSize(width: 640, height: 205)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("无法创建 dmg 背景画布")
}
bitmap.size = canvasSize

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor(calibratedRed: 0.965, green: 0.976, blue: 0.992, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

guard
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("无法生成 dmg 背景图")
}

NSGraphicsContext.restoreGraphicsState()
try pngData.write(to: URL(fileURLWithPath: outputPath))
