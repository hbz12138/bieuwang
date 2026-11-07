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

// MARK: - 新建 / 修改提醒（AppKit 表单）

final class EditorController: NSObject {

    private let library: ReminderLibrary
    private var draft: Reminder
    private let isNew: Bool
    private let onDone: () -> Void

    private(set) var window: NSWindow!
    /// 保存成功后把那条提醒留一份，调用方据此决定"跳到哪个分栏让你看见它"
    private(set) var lastSaved: Reminder?
    private weak var parent: NSWindow?
    private var form: NSStackView!

    private let titleField = NSTextField()
    private let noteField = NSTextField()
    private let kindPopup = NSPopUpButton()
    private let datePicker = NSDatePicker()
    private let freqPopup = NSPopUpButton()
    private let weekdayPopup = NSPopUpButton()
    private let monthDayField = NSTextField()
    private let timePicker = NSDatePicker()

    init(library: ReminderLibrary,
         existing: Reminder?,
         defaultKind: ReminderKind,
         onDone: @escaping () -> Void) {
        self.library = library
        self.onDone = onDone
        self.isNew = existing == nil
        self.draft = existing ?? Reminder(title: "", kind: defaultKind)

        super.init()
        buildWindow()
        buildForm()
    }

    // MARK: 窗口

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        window.title = isNew ? "新建提醒" : "修改提醒"
        window.isReleasedWhenClosed = false

        form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 12
        form.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(form)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            form.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            form.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            form.widthAnchor.constraint(equalToConstant: 420)
        ])
        window.contentView = container
    }

    // MARK: 表单

    private func buildForm() {
        for sub in form.arrangedSubviews {
            form.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        titleField.stringValue = draft.title
        titleField.placeholderString = "要记住什么？"
        titleField.font = .systemFont(ofSize: 14)
        titleField.widthAnchor.constraint(equalToConstant: 420).isActive = false
        addRow("", titleField, width: 350)

        kindPopup.removeAllItems()
        kindPopup.addItems(withTitles: ReminderKind.allCases.map { $0.label })
        if let index = ReminderKind.allCases.firstIndex(of: draft.kind) {
            kindPopup.selectItem(at: index)
        }
        kindPopup.target = self
        kindPopup.action = #selector(kindChanged)
        addRow("类型", kindPopup, width: 120)

        let hint = NSTextField(labelWithString: draft.kind.hint)
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        form.addArrangedSubview(hint)

        switch draft.kind {
        case .moment, .deadline:
            datePicker.datePickerElements = [.yearMonthDay, .hourMinute]
            datePicker.datePickerStyle = .textFieldAndStepper
            datePicker.dateValue = draft.primaryDate
                ?? Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            addRow(draft.kind == .deadline ? "截止" : "时间", datePicker, width: 200)

        case .recurring:
            freqPopup.removeAllItems()
            freqPopup.addItems(withTitles: RepeatFreq.allCases.map { $0.label })
            if let rule = draft.recurrence, let index = RepeatFreq.allCases.firstIndex(of: rule.freq) {
                freqPopup.selectItem(at: index)
            }
            freqPopup.target = self
            freqPopup.action = #selector(kindChanged)
            addRow("重复", freqPopup, width: 120)

            if freqPopup.indexOfSelectedItem == RepeatFreq.weekly.indexInAllCases {
                weekdayPopup.removeAllItems()
                weekdayPopup.addItems(withTitles: ["周日", "周一", "周二", "周三", "周四", "周五", "周六"])
                weekdayPopup.selectItem(at: max(0, min(6, (draft.recurrence?.weekday ?? 2) - 1)))
                addRow("星期", weekdayPopup, width: 90)
            }

            if freqPopup.indexOfSelectedItem == RepeatFreq.monthly.indexInAllCases {
                monthDayField.stringValue = "\(draft.recurrence?.monthDay ?? 1)"
                monthDayField.widthAnchor.constraint(equalToConstant: 60).isActive = false
                addRow("每月几号", monthDayField, width: 50)
            }

            timePicker.datePickerElements = [.hourMinute]
            timePicker.datePickerStyle = .textFieldAndStepper
            timePicker.dateValue = ClockText.date(from: Date(),
                                                  hour: draft.recurrence?.hour ?? 9,
                                                  minute: draft.recurrence?.minute ?? 0) ?? Date()
            addRow("时间", timePicker, width: 90)

        case .pool:
            let note = NSTextField(labelWithString: "放进池子，不会到点吵你；每天空闲时抽一件问你。")
            note.font = .systemFont(ofSize: 11)
            note.textColor = .secondaryLabelColor
            form.addArrangedSubview(note)
        }

        noteField.stringValue = draft.note
        noteField.placeholderString = "备注（可选）"
        addRow("备注", noteField, width: 350)

        if draft.kind.writesToCalendar && library.settings.calendarSyncEnabled {
            let sync = NSTextField(labelWithString: "会同步到日历「\(library.settings.calendarName)」")
            sync.font = .systemFont(ofSize: 10)
            sync.textColor = .secondaryLabelColor
            form.addArrangedSubview(sync)
        }

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(NSButton(title: "取消", target: self, action: #selector(cancel)))
        let save = NSButton(title: isNew ? "添加" : "保存", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        buttons.addArrangedSubview(save)
        buttons.widthAnchor.constraint(equalToConstant: 420).isActive = true
        form.addArrangedSubview(buttons)

        // 让窗口高度跟着内容走，避免底部按钮被裁掉
        form.layoutSubtreeIfNeeded()
        let needed = form.fittingSize.height + 36
        window.setContentSize(NSSize(width: 460, height: max(260, needed)))
    }

    private func addRow(_ label: String, _ control: NSView, width: CGFloat) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY

        if !label.isEmpty {
            let text = NSTextField(labelWithString: label)
            text.font = .systemFont(ofSize: 12)
            text.textColor = .secondaryLabelColor
            text.alignment = .right
            text.widthAnchor.constraint(equalToConstant: 60).isActive = true
            row.addArrangedSubview(text)
        }

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: width).isActive = true
        row.addArrangedSubview(control)
        form.addArrangedSubview(row)
    }

    // MARK: 交互

    @objc private func kindChanged() {
        let index = kindPopup.indexOfSelectedItem
        draft.kind = ReminderKind.allCases[max(0, min(ReminderKind.allCases.count - 1, index))]

        if draft.kind == .recurring {
            let freqIndex = freqPopup.indexOfSelectedItem
            if freqIndex >= 0 && freqIndex < RepeatFreq.allCases.count {
                draft.recurrence = Recurrence(
                    freq: RepeatFreq.allCases[freqIndex],
                    hour: Calendar.current.component(.hour, from: timePicker.dateValue),
                    minute: Calendar.current.component(.minute, from: timePicker.dateValue),
                    weekday: weekdayPopup.indexOfSelectedItem + 1,
                    monthDay: Int(monthDayField.stringValue) ?? 1
                )
            }
        }
        buildForm()
    }

    @objc private func cancel() {
        close()
    }

    @objc private func save() {
        draft.title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.title.isEmpty else {
            NSSound.beep()
            return
        }
        draft.note = noteField.stringValue

        switch draft.kind {
        case .moment:
            draft.dueAt = datePicker.dateValue
            draft.deadlineAt = nil
            draft.recurrence = nil
            draft.fireCount = 0
            draft.stageIndex = 0
        case .deadline:
            draft.deadlineAt = datePicker.dateValue
            draft.dueAt = nil
            draft.recurrence = nil
            draft.stageIndex = 0
        case .recurring:
            let hour = Calendar.current.component(.hour, from: timePicker.dateValue)
            let minute = Calendar.current.component(.minute, from: timePicker.dateValue)
            let freqIndex = max(0, freqPopup.indexOfSelectedItem)
            let rule = Recurrence(
                freq: RepeatFreq.allCases[min(freqIndex, RepeatFreq.allCases.count - 1)],
                hour: hour,
                minute: minute,
                weekday: weekdayPopup.numberOfItems > 0 ? weekdayPopup.indexOfSelectedItem + 1 : nil,
                monthDay: Int(monthDayField.stringValue) ?? nil
            )
            draft.recurrence = rule
            draft.dueAt = RecurrenceEngine.next(after: Date(), rule: rule)
            draft.pendingOccurrence = nil
            draft.fireCount = 0
        case .pool:
            draft.dueAt = nil
            draft.deadlineAt = nil
            draft.recurrence = nil
        }

        draft.snoozedUntil = nil
        draft.lastFiredAt = nil
        if draft.status != .active { draft.status = .active }

        library.upsert(draft)
        lastSaved = draft
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

extension RepeatFreq {
    var indexInAllCases: Int {
        RepeatFreq.allCases.firstIndex(of: self) ?? 0
    }
}
