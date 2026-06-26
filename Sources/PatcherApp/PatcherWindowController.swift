// 文件说明：原生补丁工具主窗口和交互逻辑

import AppKit

final class PatcherWindowController: NSWindowController {
    /// 窗口内文字、分割线和面板叠色集中配置，保持偏好设置风格统一
    enum UIStyle {
        static let windowOverlay = NSColor.white.withAlphaComponent(0.97)
        static let primaryText = NSColor.labelColor
        static let secondaryText = NSColor.secondaryLabelColor
        static let separator = NSColor.separatorColor.withAlphaComponent(0.34)
    }

    /// 页面尺寸按设计稿固定，窗口缩放时也保持偏好设置面板比例
    enum Layout {
        static let contentWidth: CGFloat = 615
        static let pageTop: CGFloat = 24
        static let pageBottom: CGFloat = 10
        static let sectionSpacing: CGFloat = 8
        static let settingsColumnGap: CGFloat = 15
        static let previewHeight: CGFloat = 116
        static let modeHeight: CGFloat = 40
        static let settingsHeight: CGFloat = 250
        static let footerHeight: CGFloat = 38
        static let cardInset: CGFloat = 12
        // 设置区是左右等宽两列，行宽固定后无控件说明行不会被 AppKit 按内容宽度居中
        static let settingsPanelContentWidth: CGFloat = (contentWidth - settingsColumnGap) / 2 - 2 * cardInset
        // AppKit 文本控件的实际高度由字体决定，这里只用于推导固定窗口高度
        private static let sectionTitleHeight: CGFloat = 16
        private static let sectionTitleSpacing: CGFloat = 6
        // 这里把窗口高度跟内容区绑定，避免底部按钮下方露出大块空白
        static let windowSize = NSSize(
            width: 680,
            height: pageTop
                + previewHeight
                + modeHeight
                + settingsHeight
                + footerHeight
                + 2 * sectionTitleHeight
                + 2 * sectionTitleSpacing
                + 3 * sectionSpacing
                + pageBottom
        )
    }

    enum ModeTag {
        static let transparent = 0
        static let solid = 1
        static let gradient = 2
    }

    let previewView = LyricPreviewView()
    let cornerRadiusSlider = NSSlider(value: 12, minValue: 0, maxValue: 40, target: nil, action: nil)
    let cornerRadiusValueLabel = NSTextField(labelWithString: "12 px")
    let materialOpacitySlider = NSSlider(value: 80, minValue: 0, maxValue: 100, target: nil, action: nil)
    let materialOpacityValueLabel = NSTextField(labelWithString: "80%")
    let startColorWell = NSColorWell()
    let endColorWell = NSColorWell()
    let directionPopup = NSPopUpButton()
    let gradientOpacitySlider = NSSlider(value: 80, minValue: 0, maxValue: 100, target: nil, action: nil)
    let gradientOpacityValueLabel = NSTextField(labelWithString: "80%")
    let lyricColorWell = NSColorWell()
    let lyricFontPopup = NSPopUpButton()
    let lyricFontSizeSlider = NSSlider(value: 23, minValue: 12, maxValue: 72, target: nil, action: nil)
    let lyricFontSizeValueLabel = NSTextField(labelWithString: "23 px")
    let lyricGradientSwitch = NSSwitch()
    let lyricGradientStartColorWell = NSColorWell()
    let lyricGradientEndColorWell = NSColorWell()
    let lyricGradientDirectionPopup = NSPopUpButton()
    let infoButton = NSButton(title: "", target: nil, action: nil)
    let resetDefaultsButton = NSButton(title: "恢复默认", target: nil, action: nil)
    let applyButton = NSButton(title: "应用更改", target: nil, action: nil)
    let statusLabel = NSTextField(labelWithString: "")
    private let runner = AdminCommandRunner()

    var modeButtons: [NSButton] = []
    var backgroundSettingsPanel: NSView?
    var transparentModeRows: [NSView] = []
    var commonBackgroundRows: [NSView] = []
    var solidModeRows: [NSView] = []
    var gradientModeRows: [NSView] = []
    var lyricSolidRows: [NSView] = []
    var lyricGradientRows: [NSView] = []
    var isUpdatingControls = false
    private var isBusy = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Layout.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = Layout.windowSize
        window.maxSize = Layout.windowSize
        window.center()

        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let backgroundView = NSView()
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = UIStyle.windowOverlay.cgColor
        backgroundView.layer?.cornerRadius = 10
        backgroundView.layer?.borderWidth = 1
        backgroundView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
        backgroundView.layer?.masksToBounds = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundView)
        pin(backgroundView, to: contentView)

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = Layout.sectionSpacing
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: Layout.pageTop),
            rootStack.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            rootStack.widthAnchor.constraint(equalToConstant: Layout.contentWidth)
        ])

        [makePreviewSection(), makeModeSection(), makeSettingsSection(), makeFooterSection()].forEach {
            rootStack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }

        configureControls()
        isUpdatingControls = true
        applyDefaultControlValues()
        loadCurrentConfigIntoControls()
        isUpdatingControls = false
        updateFooterStatus("")
        updatePreview()
    }

    @objc func modeChanged(_ sender: NSButton) {
        selectMode(tag: sender.tag)
        updateSettingsVisibility()
        markPendingChange()
        updatePreview()
    }

    @objc func appearanceChanged() {
        updateValueLabels()
        markPendingChange()
        updatePreview()
    }

    @objc func lyricGradientChanged() {
        updateSettingsVisibility()
        appearanceChanged()
    }

    @objc func resetDefaultSettings() {
        runPrivilegedAction(
            arguments: ["restore", "--yes", "--quit-netease"],
            launchNeteaseAfterSuccess: true,
            runningTitle: "恢复中...",
            runningStatus: "正在恢复默认"
        )
    }

    @objc func applyPatch() {
        runPrivilegedAction(arguments: applyArguments(), launchNeteaseAfterSuccess: true)
    }

    @objc func showAppInfo() {
        presentAppInfo()
    }

    func showMainWindow() {
        NSApp.unhide(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func runPrivilegedAction(
        arguments: [String],
        launchNeteaseAfterSuccess: Bool = false,
        runningTitle: String = "应用中...",
        runningStatus: String = "正在应用更改"
    ) {
        guard !isBusy else {
            return
        }
        isBusy = true
        setControlsEnabled(false)
        applyButton.title = runningTitle
        applyFooterButtonTint(applyButton)
        updateFooterStatus(runningStatus)

        let cliPath = bundledCLIURL().path
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let output = try self.runner.run(executablePath: cliPath, arguments: arguments)
                DispatchQueue.main.async {
                    if launchNeteaseAfterSuccess {
                        self.restartNeteaseMusic()
                    }
                    self.finishAction(status: "")
                    _ = output
                }
            } catch {
                DispatchQueue.main.async {
                    if self.isUserCancelled(error) {
                        self.finishAction(status: "修改未生效")
                        return
                    }

                    self.finishAction(status: "应用失败")
                }
            }
        }
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        if case AdminCommandRunnerError.userCancelled = error {
            return true
        }

        let text = displayText(for: error).trimmingCharacters(in: .whitespacesAndNewlines)
        return text == "用户已取消。" || text == "User canceled."
    }

    private func finishAction(status: String) {
        isBusy = false
        applyButton.title = "应用更改"
        applyFooterButtonTint(applyButton)
        setControlsEnabled(true)
        updateFooterStatus(status)
    }

    private func setControlsEnabled(_ enabled: Bool) {
        let controls: [NSControl] = [
            directionPopup,
            startColorWell,
            endColorWell,
            cornerRadiusSlider,
            materialOpacitySlider,
            gradientOpacitySlider,
            lyricColorWell,
            lyricFontPopup,
            lyricFontSizeSlider,
            lyricGradientSwitch,
            lyricGradientStartColorWell,
            lyricGradientEndColorWell,
            lyricGradientDirectionPopup,
            infoButton,
            resetDefaultsButton,
            applyButton
        ]
        controls.forEach { $0.isEnabled = enabled }
        modeButtons.forEach { $0.isEnabled = enabled }
    }

    private func restartNeteaseMusic() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            _ = ProcessRunner.runQuietly("/usr/bin/open", arguments: [defaultAppPath])
        }
    }

    private func displayText(for error: Error) -> String {
        if let patchError = error as? PatchCLIError {
            return patchError.description.isEmpty ? "操作失败，但底层工具没有返回错误详情" : patchError.description
        }

        let description = error.localizedDescription
        return description.isEmpty ? String(describing: error) : description
    }

    private func bundledCLIURL() -> URL {
        Bundle.main.resourceURL!.appendingPathComponent("nmlrc-bg-patcher")
    }
}

extension PatcherWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 点击红色关闭按钮时只收起主窗口，应用继续留在后台等待再次打开
        sender.orderOut(nil)
        NSApp.hide(nil)
        return false
    }
}
