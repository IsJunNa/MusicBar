// 文件说明：原生补丁工具主窗口控件状态换算

import AppKit

extension PatcherWindowController {
    /// 从用户已有配置恢复控件状态，缺失的新字段使用当前默认值
    func loadCurrentConfigIntoControls() {
        guard let config = try? ConfigStore().read() else {
            updateSettingsVisibility()
            return
        }

        switch config.mode {
        case .transparent:
            selectMode(tag: ModeTag.transparent)
        case .solid:
            selectMode(tag: ModeTag.solid)
        case .gradient:
            selectMode(tag: ModeTag.gradient)
        }

        startColorWell.color = HexColor.color(from: config.gradientStartColor, fallback: startColorWell.color)
        endColorWell.color = HexColor.color(from: config.gradientEndColor, fallback: endColorWell.color)
        cornerRadiusSlider.doubleValue = config.cornerRadius
        materialOpacitySlider.doubleValue = config.opacity * 100
        gradientOpacitySlider.doubleValue = config.opacity * 100
        selectDirection(config.gradientDirection, in: directionPopup)

        let lyricColor = config.lyricColor ?? config.lyricPlayedColor ?? "#FFFFFF"
        lyricColorWell.color = HexColor.color(from: lyricColor, fallback: lyricColorWell.color)
        selectLyricFont(named: config.lyricFontName ?? LyricFontOption.pingFangSemibold.rawValue)
        lyricFontSizeSlider.doubleValue = config.lyricFontSize ?? 23
        lyricGradientSwitch.state = config.lyricGradientEnabled == true ? .on : .off
        lyricGradientStartColorWell.color = HexColor.color(from: config.lyricGradientStartColor ?? "#FFFFFF", fallback: lyricGradientStartColorWell.color)
        lyricGradientEndColorWell.color = HexColor.color(from: config.lyricGradientEndColor ?? "#9FD8FF", fallback: lyricGradientEndColorWell.color)
        selectDirection(config.lyricGradientDirection ?? .leftToRight, in: lyricGradientDirectionPopup)

        updateSettingsVisibility()
        updateValueLabels()
    }

    /// 恢复默认外观值，不会直接写入补丁配置
    func applyDefaultControlValues() {
        selectMode(tag: ModeTag.solid)
        selectDirection(.leftToRight, in: directionPopup)
        startColorWell.color = NSColor(calibratedRed: 139 / 255, green: 115 / 255, blue: 1, alpha: 1)
        endColorWell.color = NSColor(calibratedRed: 1, green: 122 / 255, blue: 138 / 255, alpha: 1)
        cornerRadiusSlider.doubleValue = 12
        materialOpacitySlider.doubleValue = 80
        gradientOpacitySlider.doubleValue = 80

        lyricColorWell.color = .white
        selectLyricFont(named: LyricFontOption.pingFangSemibold.rawValue)
        lyricFontSizeSlider.doubleValue = 23
        lyricGradientSwitch.state = .off
        lyricGradientStartColorWell.color = .white
        lyricGradientEndColorWell.color = NSColor(calibratedRed: 159 / 255, green: 216 / 255, blue: 1, alpha: 1)
        selectDirection(.leftToRight, in: lyricGradientDirectionPopup)

        updateSettingsVisibility()
        updateValueLabels()
    }

    /// 用户改动控件后只更新预览，不再显示待应用状态提示
    func markPendingChange() {
        guard !isUpdatingControls else {
            return
        }
    }

    /// 更新底部状态文本，空字符串会保持界面安静
    func updateFooterStatus(_ value: String) {
        statusLabel.stringValue = value
    }

    /// 根据背景模式和字体渐变开关隐藏当前无效设置
    func updateSettingsVisibility() {
        let mode = selectedModeTag()
        let isSolid = mode == ModeTag.solid
        let isGradient = mode == ModeTag.gradient
        backgroundSettingsPanel?.isHidden = false
        commonBackgroundRows.forEach { $0.isHidden = mode == ModeTag.transparent }
        solidModeRows.forEach { $0.isHidden = !isSolid }
        gradientModeRows.forEach { $0.isHidden = !isGradient }
        transparentModeRows.forEach { $0.isHidden = mode != ModeTag.transparent }

        let lyricGradientEnabled = lyricGradientSwitch.state == .on
        lyricSolidRows.forEach { $0.isHidden = lyricGradientEnabled }
        lyricGradientRows.forEach { $0.isHidden = !lyricGradientEnabled }
    }

    /// 同步 Slider 右侧数值，让用户调整时有明确反馈
    func updateValueLabels() {
        cornerRadiusValueLabel.stringValue = "\(Int(cornerRadiusSlider.doubleValue)) px"
        materialOpacityValueLabel.stringValue = "\(Int(materialOpacitySlider.doubleValue))%"
        gradientOpacityValueLabel.stringValue = "\(Int(gradientOpacitySlider.doubleValue))%"
        lyricFontSizeValueLabel.stringValue = "\(Int(lyricFontSizeSlider.doubleValue)) px"
    }

    /// 将控件当前值投递给顶部预览，不触发真实补丁写入
    func updatePreview() {
        previewView.modeTag = selectedModeTag()
        previewView.startColor = startColorWell.color
        previewView.endColor = endColorWell.color
        previewView.gradientDirection = selectedDirection(in: directionPopup)
        previewView.opacity = selectedOpacity()
        previewView.cornerRadius = cornerRadiusSlider.doubleValue
        previewView.lyricColor = lyricColorWell.color
        previewView.lyricFontName = selectedLyricFontName()
        previewView.lyricFontSize = lyricFontSizeSlider.doubleValue
        previewView.lyricGradientEnabled = lyricGradientSwitch.state == .on
        previewView.lyricGradientStartColor = lyricGradientStartColorWell.color
        previewView.lyricGradientEndColor = lyricGradientEndColorWell.color
        previewView.lyricGradientDirection = selectedDirection(in: lyricGradientDirectionPopup)
    }

    /// 把普通控件值转换成 CLI 参数，应用按钮只依赖这一处输出
    func applyArguments() -> [String] {
        [
            "apply",
            "--mode", selectedMode(),
            "--blur-material", BlurMaterial.ultraThin.rawValue,
            "--gradient-start", HexColor.hex(from: startColorWell.color),
            "--gradient-end", HexColor.hex(from: endColorWell.color),
            "--direction", selectedDirection(in: directionPopup).rawValue,
            "--opacity", String(format: "%.2f", selectedOpacity()),
            "--corner-radius", String(format: "%.0f", cornerRadiusSlider.doubleValue),
            "--lyric-color", HexColor.hex(from: lyricColorWell.color),
            "--lyric-font-name", selectedLyricFontName(),
            "--lyric-font-size", String(format: "%.0f", lyricFontSizeSlider.doubleValue),
            "--lyric-gradient-enabled", lyricGradientSwitch.state == .on ? "true" : "false",
            "--lyric-gradient-start", HexColor.hex(from: lyricGradientStartColorWell.color),
            "--lyric-gradient-end", HexColor.hex(from: lyricGradientEndColorWell.color),
            "--lyric-gradient-direction", selectedDirection(in: lyricGradientDirectionPopup).rawValue,
            "--yes",
            "--quit-netease"
        ]
    }

    /// 当前单选模式转换为补丁工具识别的模式值
    func selectedMode() -> String {
        switch selectedModeTag() {
        case ModeTag.transparent:
            return PatchMode.transparent.rawValue
        case ModeTag.gradient:
            return PatchMode.gradient.rawValue
        case ModeTag.solid:
            return PatchMode.solid.rawValue
        default:
            return PatchMode.solid.rawValue
        }
    }

    /// 背景不透明度 Slider 在 UI 中是 0 到 100，写配置时转换为 0 到 1
    func selectedOpacity() -> Double {
        let slider = selectedModeTag() == ModeTag.gradient ? gradientOpacitySlider : materialOpacitySlider
        return slider.doubleValue / 100
    }

    /// 从指定方向下拉中读取方向值
    func selectedDirection(in popup: NSPopUpButton) -> GradientDirection {
        let index = popup.indexOfSelectedItem
        guard GradientDirection.allCases.indices.contains(index) else {
            return .leftToRight
        }
        return GradientDirection.allCases[index]
    }

    /// 根据配置中的方向值反选对应下拉
    func selectDirection(_ direction: GradientDirection, in popup: NSPopUpButton) {
        guard let index = GradientDirection.allCases.firstIndex(of: direction) else {
            return
        }
        popup.selectItem(at: index)
    }

    /// 读取字体下拉选中的 NSFont 名称
    func selectedLyricFontName() -> String {
        let index = lyricFontPopup.indexOfSelectedItem
        guard LyricFontOption.allCases.indices.contains(index) else {
            return LyricFontOption.pingFangSemibold.rawValue
        }
        return LyricFontOption.allCases[index].rawValue
    }

    /// 根据配置中的字体名称反选下拉，未知字体回退到苹方半粗
    func selectLyricFont(named fontName: String) {
        let options = LyricFontOption.allCases
        let index = options.firstIndex { $0.rawValue == fontName } ?? 0
        lyricFontPopup.selectItem(at: index)
    }

    /// 返回当前背景模式按钮 tag，默认纯色符合工具初始状态
    func selectedModeTag() -> Int {
        modeButtons.first(where: { $0.state == .on })?.tag ?? ModeTag.solid
    }

    /// 保持系统 Radio 行为清晰，三个背景模式只允许一个打开
    func selectMode(tag: Int) {
        modeButtons.forEach { $0.state = $0.tag == tag ? .on : .off }
    }
}
