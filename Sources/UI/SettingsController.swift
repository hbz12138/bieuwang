// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import AppKit
import UniformTypeIdentifiers

// MARK: - 设置

final class SettingsController: NSObject {

    private let library: ReminderLibrary
    private let onDone: () -> Void

    private(set) var window: NSWindow!
    private weak var parent: NSWindow?

    private let calendarToggle = NSButton(checkboxWithTitle: "把提醒写进系统日历（随 iCloud 同步到手机）",
                                          target: nil, action: nil)
    private let pathLabel = NSTextField(labelWithString: "")
    private let nagToggle = NSButton(checkboxWithTitle: "没处理完就再追一次（15 分钟、1 小时后）",
                                     target: nil, action: nil)
    private let launchToggle = NSButton(checkboxWithTitle: "登录时自动启动", target: nil, action: nil)
    private let quietFrom = NSTextField()
    private let quietTo = NSTextField()
    private let nudgeField = NSTextField()

    init(library: ReminderLibrary, onDone: @escaping () -> Void) {
        self.library = library
        self.onDone = onDone
        super.init()
        build()
    }

    private func build() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        window.title = "别忘 · 设置"
        window.isReleasedWhenClosed = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 日历
        let calendarBox = makeBox(title: "日历同步")
        calendarToggle.state = library.settings.calendarSyncEnabled ? .on : .off
        calendarBox.addArrangedSubview(calendarToggle)

        let calendarHint = NSTextField(wrappingLabelWithString:
            "写进一个单独叫「\(library.settings.calendarName)」的日历，不混进你原有的日历。点「稍后」时，定时类提醒会就地改时间，手机日历也跟着改。")
        calendarHint.font = .systemFont(ofSize: 10)
        calendarHint.textColor = .secondaryLabelColor
        calendarHint.preferredMaxLayoutWidth = 440
        calendarBox.addArrangedSubview(calendarHint)

        let openCalendar = NSButton(title: "打开日历看看", target: self, action: #selector(openCalendarApp))
        openCalendar.isBordered = false
        openCalendar.contentTintColor = .linkColor
        openCalendar.font = .systemFont(ofSize: 11)
        calendarBox.addArrangedSubview(openCalendar)

        // 数据
        let dataBox = makeBox(title: "数据位置")
        pathLabel.stringValue = library.fileURL.path
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.preferredMaxLayoutWidth = 440
        dataBox.addArrangedSubview(pathLabel)

        let dataButtons = NSStackView()
        dataButtons.orientation = .horizontal
        dataButtons.spacing = 8
        dataButtons.addArrangedSubview(NSButton(title: "更改…", target: self, action: #selector(changeDirectory)))
        dataButtons.addArrangedSubview(NSButton(title: "在访达中显示", target: self, action: #selector(reveal)))
        dataBox.addArrangedSubview(dataButtons)

        let dataHint = NSTextField(wrappingLabelWithString:
            "提醒数据就是这一个 JSON 文件。换电脑时把它和 App 一起拷过去即可。")
        dataHint.font = .systemFont(ofSize: 10)
        dataHint.textColor = .tertiaryLabelColor
        dataHint.preferredMaxLayoutWidth = 440
        dataBox.addArrangedSubview(dataHint)

        // 提醒方式
        let behaviorBox = makeBox(title: "提醒方式")
        nagToggle.state = library.settings.nagEnabled ? .on : .off
        behaviorBox.addArrangedSubview(nagToggle)
        launchToggle.state = library.settings.launchAtLogin ? .on : .off
        behaviorBox.addArrangedSubview(launchToggle)

        let quietRow = NSStackView()
        quietRow.orientation = .horizontal
        quietRow.spacing = 6
        quietRow.addArrangedSubview(NSTextField(labelWithString: "免打扰"))
        quietFrom.stringValue = library.settings.quietFrom
        quietFrom.widthAnchor.constraint(equalToConstant: 56).isActive = true
        quietTo.stringValue = library.settings.quietTo
        quietTo.widthAnchor.constraint(equalToConstant: 56).isActive = true
        quietRow.addArrangedSubview(quietFrom)
        quietRow.addArrangedSubview(NSTextField(labelWithString: "到"))
        quietRow.addArrangedSubview(quietTo)
        behaviorBox.addArrangedSubview(quietRow)

        let nudgeRow = NSStackView()
        nudgeRow.orientation = .horizontal
        nudgeRow.spacing = 6
        nudgeRow.addArrangedSubview(NSTextField(labelWithString: "待办池抽问时刻"))
        nudgeField.stringValue = library.settings.idleNudgeTimes.joined(separator: ", ")
        nudgeField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        nudgeRow.addArrangedSubview(nudgeField)
        behaviorBox.addArrangedSubview(nudgeRow)

        let nudgeHint = NSTextField(labelWithString: "一次只抽一件。留空则不主动问。")
        nudgeHint.font = .systemFont(ofSize: 10)
        nudgeHint.textColor = .tertiaryLabelColor
        behaviorBox.addArrangedSubview(nudgeHint)

        // 按钮
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.addArrangedSubview(NSButton(title: "导出 .ics…", target: self, action: #selector(exportICS)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(NSButton(title: "取消", target: self, action: #selector(cancel)))
        let save = NSButton(title: "保存", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        buttons.addArrangedSubview(save)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: 440).isActive = true

        stack.addArrangedSubview(calendarBox)
        stack.addArrangedSubview(dataBox)
        stack.addArrangedSubview(behaviorBox)
        stack.addArrangedSubview(buttons)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])
        window.contentView = container

        stack.layoutSubtreeIfNeeded()
        let needed = stack.fittingSize.height + 40
        window.setContentSize(NSSize(width: 520, height: max(320, needed)))
    }

    private func makeBox(title: String) -> NSStackView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 6

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        box.addArrangedSubview(label)
        return box
    }

    // MARK: 动作

    @objc private func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    @objc private func changeDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "把提醒放在这里"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        library.relocate(to: url)
        pathLabel.stringValue = library.fileURL.path
    }

    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([library.fileURL])
    }

    @objc private func exportICS() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "别忘.ics"
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ICSExporter.export(library.active).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func cancel() {
        close()
    }

    @objc private func save() {
        library.settings.calendarSyncEnabled = calendarToggle.state == .on
        library.settings.nagEnabled = nagToggle.state == .on
        library.settings.launchAtLogin = launchToggle.state == .on
        library.settings.quietFrom = quietFrom.stringValue
        library.settings.quietTo = quietTo.stringValue
        library.settings.idleNudgeTimes = nudgeField.stringValue
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { ClockText.parse($0) != nil }

        library.saveNow()
        if library.settings.calendarSyncEnabled {
            library.repairCalendarLinks()
        }
        LaunchAtLogin.set(library.settings.launchAtLogin)

        onDone()
        close()
    }

    private func close() {
        if let parent, window.sheetParent != nil {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }

    func present(asSheetOf parent: NSWindow?) {
        self.parent = parent
        if let parent, parent.isVisible {
            parent.beginSheet(window, completionHandler: nil)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
