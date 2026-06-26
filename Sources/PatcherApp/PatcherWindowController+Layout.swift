// 文件说明：原生补丁工具主窗口布局构建

import AppKit

extension PatcherWindowController {
    /// 统一配置所有系统控件的选项、尺寸和回调
    func configureControls() {
        directionPopup.addItems(withTitles: GradientDirection.allCases.map(\.displayName))
        lyricGradientDirectionPopup.addItems(withTitles: GradientDirection.allCases.map(\.displayName))
        lyricFontPopup.addItems(withTitles: LyricFontOption.allCases.map(\.displayName))

        [directionPopup, lyricGradientDirectionPopup, lyricFontPopup].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .small
            $0.target = self
            $0.action = #selector(appearanceChanged)
            $0.widthAnchor.constraint(equalToConstant: 140).isActive = true
        }

        [
            startColorWell,
            endColorWell,
            lyricColorWell,
            lyricGradientStartColorWell,
            lyricGradientEndColorWell
        ].forEach {
            $0.target = self
            $0.action = #selector(appearanceChanged)
            $0.widthAnchor.constraint(equalToConstant: 42).isActive = true
            $0.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }

        [cornerRadiusSlider, materialOpacitySlider, gradientOpacitySlider, lyricFontSizeSlider].forEach {
            $0.target = self
            $0.action = #selector(appearanceChanged)
            $0.controlSize = .small
        }

        lyricGradientSwitch.target = self
        lyricGradientSwitch.action = #selector(lyricGradientChanged)

        infoButton.title = "关于与反馈"
        infoButton.bezelStyle = .rounded
        infoButton.controlSize = .regular
        infoButton.font = .systemFont(ofSize: 12, weight: .medium)
        infoButton.isBordered = true
        infoButton.bezelColor = .controlAccentColor
        infoButton.contentTintColor = .white
        applyFooterButtonTint(infoButton)
        infoButton.target = self
        infoButton.action = #selector(showAppInfo)
        infoButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true

        configureStatusLabel()

        resetDefaultsButton.target = self
        resetDefaultsButton.action = #selector(resetDefaultSettings)
        configureActionButton(resetDefaultsButton)

        applyButton.target = self
        applyButton.action = #selector(applyPatch)
        applyButton.keyEquivalent = "\r"
        configureActionButton(applyButton, prominent: true, width: 96)
    }

    /// 创建顶部歌词效果预览区域
    func makePreviewSection() -> NSView {
        previewView.heightAnchor.constraint(equalToConstant: Layout.previewHeight).isActive = true
        return previewView
    }

    /// 创建背景模式区域，单选按钮保持 AppKit 原生样式
    func makeModeSection() -> NSView {
        let panel = GlassPanelView(material: .underWindowBackground, cornerRadius: 10, overlayAlpha: 0.07, borderAlpha: 0.24)
        panel.heightAnchor.constraint(equalToConstant: Layout.modeHeight).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 38
        modeButtons = [
            makeModeButton("透明", tag: ModeTag.transparent),
            makeModeButton("纯色", tag: ModeTag.solid),
            makeModeButton("渐变", tag: ModeTag.gradient)
        ]
        modeButtons.forEach(row.addArrangedSubview)
        install(row, in: panel, insets: NSEdgeInsets(top: 0, left: Layout.cardInset, bottom: 0, right: Layout.cardInset))

        return makeSectionStack(title: "背景模式", content: panel)
    }

    /// 创建左右双列设置区域
    func makeSettingsSection() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = Layout.settingsColumnGap
        row.distribution = .fillEqually
        row.heightAnchor.constraint(equalToConstant: Layout.settingsHeight).isActive = true
        row.addArrangedSubview(makeBackgroundSettingsPanel())
        row.addArrangedSubview(makeLyricSettingsPanel())
        return makeSectionStack(title: "设置", content: row)
    }

    /// 创建左侧背景相关设置卡片，具体可调项由背景模式决定
    func makeBackgroundSettingsPanel() -> NSView {
        let transparentRow = makeInfoSettingRow(title: "背景透明", detail: "当前模式无背景参数")
        let radiusRow = makeSettingRow(title: "圆角半径", control: makeSliderControl(slider: cornerRadiusSlider, valueLabel: cornerRadiusValueLabel))
        let backgroundColorRow = makeSettingRow(title: "背景颜色", control: startColorWell)
        let solidOpacityRow = makeSettingRow(title: "背景不透明度", control: makeSliderControl(slider: materialOpacitySlider, valueLabel: materialOpacityValueLabel))
        let gradientEndRow = makeSettingRow(title: "结束颜色", control: endColorWell)
        let gradientDirectionRow = makeSettingRow(title: "方向", control: directionPopup)
        let gradientOpacityRow = makeSettingRow(title: "渐变不透明度", control: makeSliderControl(slider: gradientOpacitySlider, valueLabel: gradientOpacityValueLabel))

        transparentModeRows = [transparentRow]
        commonBackgroundRows = [radiusRow, backgroundColorRow]
        solidModeRows = [solidOpacityRow]
        gradientModeRows = [gradientEndRow, gradientDirectionRow, gradientOpacityRow]

        let panel = makeSettingsPanel(rows: [
            transparentRow,
            radiusRow,
            backgroundColorRow,
            solidOpacityRow,
            gradientEndRow,
            gradientDirectionRow,
            gradientOpacityRow
        ])
        backgroundSettingsPanel = panel
        return panel
    }

    /// 创建右侧歌词相关设置卡片
    func makeLyricSettingsPanel() -> NSView {
        let lyricColorRow = makeSettingRow(title: "歌词颜色", control: lyricColorWell)
        let fontRow = makeSettingRow(title: "字体", control: lyricFontPopup)
        let fontSizeRow = makeSettingRow(title: "字体大小", control: makeSliderControl(slider: lyricFontSizeSlider, valueLabel: lyricFontSizeValueLabel))
        let gradientSwitchRow = makeSettingRow(title: "字体渐变", control: lyricGradientSwitch)
        let gradientStartRow = makeSettingRow(title: "文字起始色", control: lyricGradientStartColorWell)
        let gradientEndRow = makeSettingRow(title: "文字结束色", control: lyricGradientEndColorWell)
        let gradientDirectionRow = makeSettingRow(title: "文字方向", control: lyricGradientDirectionPopup)

        lyricSolidRows = [lyricColorRow]
        lyricGradientRows = [gradientStartRow, gradientEndRow, gradientDirectionRow]

        return makeSettingsPanel(rows: [
            lyricColorRow,
            fontRow,
            fontSizeRow,
            gradientSwitchRow,
            gradientStartRow,
            gradientEndRow,
            gradientDirectionRow
        ])
    }

    /// 设置卡片只负责承载系统原生控件，行高和内边距按设计稿固定
    func makeSettingsPanel(rows: [NSView]) -> NSView {
        let panel = GlassPanelView(material: .underWindowBackground, cornerRadius: 10, overlayAlpha: 0.1, borderAlpha: 0.24)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        rows.forEach {
            stack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalToConstant: Layout.settingsPanelContentWidth).isActive = true
        }
        install(stack, in: panel, insets: NSEdgeInsets(top: Layout.cardInset, left: Layout.cardInset, bottom: Layout.cardInset, right: Layout.cardInset))
        return panel
    }

    /// 单行设置项承载左侧说明和右侧控件，避免普通用户界面出现开发者式密集配置
    func makeSettingRow(title: String, detail: String? = nil, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: 35).isActive = true

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(settingTitle(title))
        if let detail {
            textStack.addArrangedSubview(settingDetail(detail))
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(control)
        return row
    }

    /// 无控件说明行只承载文案，避免空控件影响标题左对齐
    func makeInfoSettingRow(title: String, detail: String) -> NSView {
        let row = NSView()
        row.heightAnchor.constraint(equalToConstant: 35).isActive = true

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let titleLabel = settingTitle(title)
        let detailLabel = settingDetail(detail)
        titleLabel.alignment = .left
        detailLabel.alignment = .left
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        detailLabel.setContentHuggingPriority(.required, for: .horizontal)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)

        textStack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(textStack)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    /// 组合原生 Slider 和右侧数值文本
    func makeSliderControl(slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        slider.widthAnchor.constraint(equalToConstant: 104).isActive = true
        valueLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true
        valueLabel.alignment = .right
        valueLabel.font = .systemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = UIStyle.primaryText
        stack.addArrangedSubview(slider)
        stack.addArrangedSubview(valueLabel)
        return stack
    }

    /// 创建原生 Radio 按钮并绑定背景模式 tag
    func makeModeButton(_ title: String, tag: Int) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(modeChanged(_:)))
        button.tag = tag
        button.font = .systemFont(ofSize: 12, weight: .regular)
        button.contentTintColor = UIStyle.primaryText
        return button
    }

    /// 创建带小标题的纵向模块
    func makeSectionStack(title: String, content: NSView) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        let titleLabel = sectionTitle(title)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(content)
        titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// 创建模块标题文本
    func sectionTitle(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIStyle.primaryText
        return label
    }

    /// 创建设置行主标签
    func settingTitle(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = UIStyle.primaryText
        return label
    }

    /// 创建设置行说明文本
    func settingDetail(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 10)
        label.textColor = UIStyle.secondaryText
        return label
    }

    /// 将子视图按指定边距固定到容器
    func install(_ view: NSView, in container: NSView, insets: NSEdgeInsets) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -insets.bottom)
        ])
    }

    /// 将子视图贴满容器
    func pin(_ view: NSView, to container: NSView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
