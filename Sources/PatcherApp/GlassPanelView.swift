// 文件说明：原生毛玻璃分组面板

import AppKit

final class GlassPanelView: NSVisualEffectView {
    /// 统一承载偏好设置里的浅色卡片，避免窗口在白色背景上发灰
    init(
        material: NSVisualEffectView.Material = .contentBackground,
        cornerRadius: CGFloat = 16,
        overlayAlpha: CGFloat = 0.16,
        borderAlpha: CGFloat = 0.35
    ) {
        super.init(frame: .zero)
        self.material = material == .underWindowBackground ? .contentBackground : material
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        let panelOverlayAlpha = max(overlayAlpha, 0.9)
        layer?.cornerRadius = cornerRadius
        layer?.backgroundColor = NSColor.white.withAlphaComponent(panelOverlayAlpha).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        nil
    }
}
