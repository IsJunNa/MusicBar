// 文件说明：桌面歌词背景效果预览视图

import AppKit

final class LyricPreviewView: NSVisualEffectView {
    var modeTag: Int = 0 {
        didSet {
            updateAppearance()
        }
    }

    var startColor: NSColor = NSColor(calibratedRed: 139 / 255, green: 115 / 255, blue: 1, alpha: 1) {
        didSet {
            updateAppearance()
        }
    }

    var endColor: NSColor = NSColor(calibratedRed: 1, green: 122 / 255, blue: 138 / 255, alpha: 1) {
        didSet {
            updateAppearance()
        }
    }

    var gradientDirection: GradientDirection = .leftToRight {
        didSet {
            updateAppearance()
        }
    }

    var lyricColor: NSColor = .white {
        didSet {
            updateLyricText()
        }
    }

    var lyricFontName: String = LyricFontOption.pingFangSemibold.rawValue {
        didSet {
            updateLyricText()
        }
    }

    var lyricFontSize: Double = 23 {
        didSet {
            updateLyricText()
        }
    }

    var lyricGradientEnabled: Bool = false {
        didSet {
            updateLyricText()
        }
    }

    var lyricGradientStartColor: NSColor = .white {
        didSet {
            updateLyricText()
        }
    }

    var lyricGradientEndColor: NSColor = NSColor(calibratedRed: 159 / 255, green: 216 / 255, blue: 1, alpha: 1) {
        didSet {
            updateLyricText()
        }
    }

    var lyricGradientDirection: GradientDirection = .leftToRight {
        didSet {
            updateLyricText()
        }
    }

    var cornerRadius: Double = 12 {
        didSet {
            lyricContainerView.layer?.cornerRadius = CGFloat(cornerRadius)
            lyricGlassView.layer?.cornerRadius = CGFloat(cornerRadius)
            lyricBackgroundView.layer?.cornerRadius = CGFloat(cornerRadius)
            gradientLayer.cornerRadius = CGFloat(cornerRadius)
        }
    }

    var opacity: Double = 0.8 {
        didSet {
            updateAppearance()
        }
    }

    private let lyricContainerView = NSView()
    private let lyricGlassView = NSVisualEffectView()
    private let lyricBackgroundView = NSView()
    private let lyricLabel = LyricPreviewLabelView()
    private let gradientLayer = CAGradientLayer()
    private let previewLyricText = "陪伴你 一直到 故事给说完"
    private let lyricGlassWidth: CGFloat = 590
    private let lyricHorizontalPadding: CGFloat = 24
    private var lastLayoutWidth: CGFloat = 0
    private var lyricGlassWidthConstraint: NSLayoutConstraint?
    private var lyricGlassHeightConstraint: NSLayoutConstraint?
    private var lyricLabelWidthConstraint: NSLayoutConstraint?
    private var lyricLabelHeightConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configurePreviewGlass()
        configureLyricGlass()
        configureLyricLabel()
        updateAppearance()
        updateLyricText()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = lyricBackgroundView.bounds
        let availableWidth = floor(effectiveLyricGlassWidth)
        if availableWidth != lastLayoutWidth {
            lastLayoutWidth = availableWidth
            updateLyricText()
        }
    }

    /// 顶部预览卡片使用浅色内容底，避免白色环境下被系统材质染灰
    private func configurePreviewGlass() {
        material = .contentBackground
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.86).cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
    }

    /// 歌词条使用独立背景层承载效果，避免设置预览和文字混在同一层
    private func configureLyricGlass() {
        lyricContainerView.wantsLayer = true
        lyricContainerView.layer?.cornerRadius = CGFloat(cornerRadius)
        lyricContainerView.layer?.masksToBounds = true
        lyricContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lyricContainerView)

        // 宽高后续会跟随预览区域和歌词字号变化，这里先保存约束引用方便更新
        let widthConstraint = lyricContainerView.widthAnchor.constraint(equalToConstant: lyricGlassWidth)
        let heightConstraint = lyricContainerView.heightAnchor.constraint(equalToConstant: 60)
        lyricGlassWidthConstraint = widthConstraint
        lyricGlassHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            lyricContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            lyricContainerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthConstraint,
            heightConstraint
        ])

        lyricGlassView.material = .hudWindow
        lyricGlassView.blendingMode = .withinWindow
        lyricGlassView.state = .active
        lyricGlassView.wantsLayer = true
        lyricGlassView.layer?.cornerRadius = CGFloat(cornerRadius)
        lyricGlassView.layer?.borderWidth = 1
        lyricGlassView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        lyricGlassView.layer?.masksToBounds = true
        lyricGlassView.translatesAutoresizingMaskIntoConstraints = false
        lyricContainerView.addSubview(lyricGlassView)
        NSLayoutConstraint.activate([
            lyricGlassView.leadingAnchor.constraint(equalTo: lyricContainerView.leadingAnchor),
            lyricGlassView.trailingAnchor.constraint(equalTo: lyricContainerView.trailingAnchor),
            lyricGlassView.topAnchor.constraint(equalTo: lyricContainerView.topAnchor),
            lyricGlassView.bottomAnchor.constraint(equalTo: lyricContainerView.bottomAnchor)
        ])

        // 这层只展示背景模式和透明度变化，让顶部预览有明确底板
        lyricBackgroundView.wantsLayer = true
        lyricBackgroundView.layer?.cornerRadius = CGFloat(cornerRadius)
        lyricBackgroundView.layer?.masksToBounds = true
        lyricBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        lyricContainerView.addSubview(lyricBackgroundView)
        NSLayoutConstraint.activate([
            lyricBackgroundView.leadingAnchor.constraint(equalTo: lyricContainerView.leadingAnchor),
            lyricBackgroundView.trailingAnchor.constraint(equalTo: lyricContainerView.trailingAnchor),
            lyricBackgroundView.topAnchor.constraint(equalTo: lyricContainerView.topAnchor),
            lyricBackgroundView.bottomAnchor.constraint(equalTo: lyricContainerView.bottomAnchor)
        ])
    }

    /// 歌词文字居中展示，用于模拟真实桌面歌词内容
    private func configureLyricLabel() {
        lyricLabel.translatesAutoresizingMaskIntoConstraints = false
        lyricContainerView.addSubview(lyricLabel)

        // 文本高度需要配合字号动态调整，避免大字号时被裁切
        let widthConstraint = lyricLabel.widthAnchor.constraint(equalToConstant: 1)
        let heightConstraint = lyricLabel.heightAnchor.constraint(equalToConstant: 31)
        lyricLabelWidthConstraint = widthConstraint
        lyricLabelHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            lyricLabel.centerXAnchor.constraint(equalTo: lyricContainerView.centerXAnchor),
            lyricLabel.centerYAnchor.constraint(equalTo: lyricContainerView.centerYAnchor),
            widthConstraint,
            heightConstraint
        ])
    }

    /// 根据当前背景模式切换预览底板，确保设置项能被用户直接看见
    private func updateAppearance() {
        guard lyricGlassView.layer != nil else {
            return
        }

        gradientLayer.removeFromSuperlayer()
        lyricGlassView.isHidden = false
        lyricGlassView.alphaValue = 1
        lyricBackgroundView.isHidden = false
        lyricBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
        lyricBackgroundView.layer?.borderWidth = 1

        switch modeTag {
        case 0:
            lyricGlassView.material = .contentBackground
            lyricGlassView.alphaValue = 1
            lyricGlassView.isHidden = true
            lyricGlassView.layer?.borderColor = NSColor.clear.cgColor
            lyricBackgroundView.isHidden = true
            lyricBackgroundView.layer?.borderColor = NSColor.clear.cgColor
        case 2:
            configureGradientLayer()
            lyricGlassView.isHidden = true
            lyricBackgroundView.isHidden = opacity <= 0
            lyricBackgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            lyricBackgroundView.layer?.addSublayer(gradientLayer)
        default:
            lyricGlassView.isHidden = true
            lyricBackgroundView.isHidden = opacity <= 0
            lyricBackgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
            lyricBackgroundView.layer?.backgroundColor = startColor.withAlphaComponent(opacity).cgColor
        }
    }

    /// 渐变模式把用户选择的背景色绘制到预览底板
    private func configureGradientLayer() {
        gradientLayer.colors = [
            startColor.withAlphaComponent(opacity).cgColor,
            endColor.withAlphaComponent(opacity).cgColor
        ]
        gradientLayer.cornerRadius = CGFloat(cornerRadius)
        gradientLayer.frame = lyricBackgroundView.bounds

        switch gradientDirection {
        case .rightToLeft:
            gradientLayer.startPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0, y: 0.5)
        case .topToBottom:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        case .bottomToTop:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        case .topLeftToBottomRight:
            gradientLayer.startPoint = CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        case .topRightToBottomLeft:
            gradientLayer.startPoint = CGPoint(x: 1, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0, y: 1)
        case .leftToRight:
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        }
    }

    /// 同步歌词字体、颜色和阴影
    private func updateLyricText() {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 8

        let fontSize = CGFloat(lyricFontSize)
        let font = NSFont(name: lyricFontName, size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .semibold)
        let displayFont = fittedLyricFont(from: font)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: displayFont,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]
        let previewText = NSMutableAttributedString(string: previewLyricText, attributes: attributes)
        let fullRange = NSRange(location: 0, length: previewText.length)
        if lyricGradientEnabled {
            previewText.addAttribute(.foregroundColor, value: lyricGradientStartColor, range: fullRange)
        } else {
            previewText.addAttribute(.foregroundColor, value: lyricColor, range: fullRange)
        }
        lyricLabel.attributedString = previewText
        lyricLabel.gradientEnabled = lyricGradientEnabled
        lyricLabel.gradientStartColor = lyricGradientStartColor
        lyricLabel.gradientEndColor = lyricGradientEndColor
        lyricLabel.gradientAngle = lyricGradientAngle
        updateLyricLayout(for: displayFont)
    }

    /// 按预览条宽度计算实际展示字号，避免大字号直接裁出容器
    private func fittedLyricFont(from font: NSFont) -> NSFont {
        let maxTextWidth = max(1, effectiveLyricTextWidth)
        let textWidth = (previewLyricText as NSString).size(withAttributes: [.font: font]).width
        let scale = min(1, maxTextWidth / max(textWidth, 1))
        let displayFontSize = max(12, font.pointSize * scale)
        return NSFont(name: font.fontName, size: displayFontSize) ?? .systemFont(ofSize: displayFontSize, weight: .semibold)
    }

    /// 字号变化时同步预览条和文字高度，让单行歌词始终垂直居中
    private func updateLyricLayout(for font: NSFont) {
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let maxGlassWidth = effectiveLyricGlassWidth
        let maxTextWidth = max(1, effectiveLyricTextWidth)
        let textWidth = ceil((previewLyricText as NSString).size(withAttributes: [.font: font]).width)

        lyricGlassWidthConstraint?.constant = maxGlassWidth
        lyricGlassHeightConstraint?.constant = max(60, lineHeight + 24)
        lyricLabelWidthConstraint?.constant = min(maxTextWidth, textWidth)
        lyricLabelHeightConstraint?.constant = max(lineHeight, font.pointSize + 8)
        needsLayout = true
        lyricContainerView.needsLayout = true
        lyricGlassView.needsLayout = true
    }

    /// 当前预览区域可用宽度优先跟随容器，避免窗口宽度变化或固定宽度偏大时文字外溢
    private var effectiveLyricGlassWidth: CGFloat {
        let containerWidth = bounds.width > 0 ? bounds.width : lyricGlassWidth
        return min(lyricGlassWidth, max(1, containerWidth - lyricHorizontalPadding))
    }

    /// 歌词文本两侧保留内边距，超大字号会基于这个范围收缩
    private var effectiveLyricTextWidth: CGFloat {
        max(1, effectiveLyricGlassWidth - lyricHorizontalPadding * 2)
    }
    private var lyricGradientAngle: CGFloat {
        switch lyricGradientDirection {
        case .rightToLeft:
            return 180
        case .topToBottom:
            return -90
        case .bottomToTop:
            return 90
        case .topLeftToBottomRight:
            return -45
        case .topRightToBottomLeft:
            return -135
        case .leftToRight:
            return 0
        }
    }
}

private final class LyricPreviewLabelView: NSView {
    var attributedString = NSAttributedString(string: "") {
        didSet {
            needsDisplay = true
        }
    }

    var gradientEnabled = false {
        didSet {
            needsDisplay = true
        }
    }

    var gradientStartColor: NSColor = .white {
        didSet {
            needsDisplay = true
        }
    }

    var gradientEndColor: NSColor = .white {
        didSet {
            needsDisplay = true
        }
    }

    var gradientAngle: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard attributedString.length > 0 else {
            return
        }

        if gradientEnabled {
            drawGradientText()
        } else {
            attributedString.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    /// 用文字 alpha 做渐变遮罩，避免 pattern color 平铺造成颜色断层
    private func drawGradientText() {
        let shadowText = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: shadowText.length)
        shadowText.addAttribute(.foregroundColor, value: gradientStartColor.withAlphaComponent(0.01), range: fullRange)
        shadowText.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])

        let maskImage = NSImage(size: bounds.size)
        maskImage.lockFocus()
        let maskText = NSMutableAttributedString(attributedString: attributedString)
        maskText.removeAttribute(.shadow, range: fullRange)
        maskText.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)
        maskText.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
        maskImage.unlockFocus()

        let textImage = NSImage(size: bounds.size)
        textImage.lockFocus()
        NSGradient(colors: [gradientStartColor, gradientEndColor])?.draw(in: bounds, angle: gradientAngle)
        maskImage.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1)
        textImage.unlockFocus()
        textImage.draw(in: bounds)
    }
}
