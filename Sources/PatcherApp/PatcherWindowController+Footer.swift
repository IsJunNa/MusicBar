// 文件说明：原生补丁工具底部操作区布局

import AppKit

extension PatcherWindowController {
    /// 创建底部操作区，包含应用信息、恢复默认和应用更改
    func makeFooterSection() -> NSView {
        let footer = NSView()
        footer.heightAnchor.constraint(equalToConstant: Layout.footerHeight).isActive = true

        let separator = NSBox()
        separator.boxType = .separator
        separator.borderColor = UIStyle.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(separator)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(row)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(infoButton)
        row.addArrangedSubview(resetDefaultsButton)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(statusLabel)
        row.addArrangedSubview(applyButton)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            row.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            row.topAnchor.constraint(equalTo: separator.bottomAnchor),
            row.bottomAnchor.constraint(equalTo: footer.bottomAnchor)
        ])

        return footer
    }

    /// 配置底部按钮的系统样式，强调按钮跟随系统 accent color
    func configureActionButton(_ button: NSButton, prominent: Bool = false, width: CGFloat = 88) {
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.isBordered = true
        applyFooterButtonTint(button)
        button.bezelColor = .controlAccentColor
        button.contentTintColor = .white
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true
    }

    /// 底部按钮统一使用白色文字和图标，避免系统圆角按钮在蓝色背景上显示黑色内容
    func applyFooterButtonTint(_ button: NSButton) {
        if let image = button.image {
            // SF Symbol 在圆角按钮里可能不跟随 contentTintColor，这里直接指定白色层级色
            let whiteSymbol = image.withSymbolConfiguration(.init(hierarchicalColor: .white)) ?? image
            whiteSymbol.isTemplate = false
            button.image = whiteSymbol
        }
        button.contentTintColor = .white
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: button.font ?? NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
    }

    /// 配置底部状态文本，用于替代成功弹窗
    func configureStatusLabel() {
        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = UIStyle.secondaryText
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.widthAnchor.constraint(equalToConstant: 170).isActive = true
    }
}
