// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import AppKit

// MARK: - 一行提醒

final class ReminderRowView: NSView {

    private let reminder: Reminder
    private let library: ReminderLibrary
    private let now: Date
    private var onOpen: (() -> Void)?
    private var onDelete: (() -> Void)?

    private let completeButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let menuButton = NSButton()
    private var tracking: NSTrackingArea?

    init(reminder: Reminder,
         now: Date,
         library: ReminderLibrary,
         onOpen: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self.reminder = reminder
        self.library = library
        self.now = now
        self.onOpen = onOpen
        self.onDelete = onDelete
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 54) }

    private func build() {
        wantsLayer = true

        completeButton.translatesAutoresizingMaskIntoConstraints = false
        completeButton.isBordered = false
        completeButton.image = NSImage(systemSymbolName: leadingSymbol, accessibilityDescription: leadingLabel)
        completeButton.contentTintColor = reminder.status == .active ? reminder.kind.tint : .secondaryLabelColor
        completeButton.target = self
        completeButton.action = #selector(leadingTapped)
        completeButton.toolTip = leadingLabel

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = reminder.title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        if reminder.status == .done {
            titleLabel.attributedStringValue = NSAttributedString(
                string: reminder.title,
                attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .font: NSFont.systemFont(ofSize: 13),
                             .foregroundColor: NSColor.secondaryLabelColor]
            )
        }

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = isOverdue ? .systemRed : .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.isBordered = false
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多")
        menuButton.contentTintColor = .tertiaryLabelColor
        menuButton.target = self
        menuButton.action = #selector(showMenu)

        addSubview(completeButton)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(menuButton)

        NSLayoutConstraint.activate([
            completeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            completeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            completeButton.widthAnchor.constraint(equalToConstant: 20),
            completeButton.heightAnchor.constraint(equalToConstant: 20),

            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 20),
            menuButton.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: completeButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2)
        ])

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 42),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    // MARK: 悬停

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onOpen?()
        } else {
            super.mouseDown(with: event)
        }
    }

    // MARK: 展示

    private var isOverdue: Bool { ScheduleRule.isOverdue(reminder, now: now) }

    private var subtitle: String {
        var parts: [String] = []

        // 已经结束的事，先说清楚它是什么状态，再说时间
        if reminder.status == .done {
            parts.append("已完成")
            if let at = reminder.completedAt {
                parts.append("\(RelativeDay.label(for: at)) \(RelativeDay.time(at))")
            }
            if !reminder.note.isEmpty { parts.append(reminder.note) }
            return parts.joined(separator: " · ")
        }

        if reminder.status == .dropped {
            parts.append("已放弃")
            if let at = reminder.droppedAt {
                parts.append("\(RelativeDay.label(for: at)) \(RelativeDay.time(at))")
            }
            if !reminder.note.isEmpty { parts.append(reminder.note) }
            return parts.joined(separator: " · ")
        }

        if let pending = reminder.pendingOccurrence, reminder.kind == .recurring {
            parts.append("本次 \(RelativeDay.label(for: pending)) 待办")
        }

        if reminder.kind == .pool {
            parts.append("待办池")
        } else if let date = reminder.primaryDate {
            parts.append("\(RelativeDay.label(for: date)) \(RelativeDay.time(date))")
        }

        if isOverdue { parts.append("已过期") }

        if let snoozed = reminder.snoozedUntil, snoozed > now {
            parts.append("压到 \(RelativeDay.time(snoozed))")
        }

        if !reminder.note.isEmpty {
            parts.append(reminder.note)
        }

        return parts.joined(separator: " · ")
    }

    // MARK: 动作

    /// 左边那个圆点：进行中时是「完成」，已结束时是「恢复」。
    /// 以前它在「完成」页里也能点，但点下去什么都不变——那是错的。
    private var leadingSymbol: String {
        guard reminder.status == .active else { return "arrow.uturn.backward.circle" }
        switch reminder.kind {
        case .moment, .pool: return "circle"
        case .deadline: return "circle.dashed"
        case .recurring: return "arrow.circlepath"
        }
    }

    private var leadingLabel: String {
        reminder.status == .active ? "完成" : "恢复"
    }

    @objc private func leadingTapped() {
        if reminder.status == .active {
            library.complete(id: reminder.id)
        } else {
            library.restore(id: reminder.id)
        }
    }

    @objc private func showMenu() {
        let menu = NSMenu()

        if reminder.status == .active {
            menu.addItem(item("10 分钟后") { [weak self] in
                guard let self else { return }
                self.library.snooze(id: self.reminder.id, until: Date().addingTimeInterval(600))
            })
            menu.addItem(item("1 小时后") { [weak self] in
                guard let self else { return }
                self.library.snooze(id: self.reminder.id, until: Date().addingTimeInterval(3600))
            })
            menu.addItem(item("今晚再说") { [weak self] in
                guard let self else { return }
                self.library.snooze(id: self.reminder.id, until: Self.tonight())
            })
            menu.addItem(.separator())
            menu.addItem(item("完成") { [weak self] in
                guard let self else { return }
                self.library.complete(id: self.reminder.id)
            })
            menu.addItem(item("不用了") { [weak self] in
                guard let self else { return }
                self.library.drop(id: self.reminder.id)
            })
        } else {
            menu.addItem(item("恢复") { [weak self] in
                guard let self else { return }
                self.library.restore(id: self.reminder.id)
            })
            menu.addItem(item("彻底删除…") { [weak self] in
                self?.onDelete?()
            })
        }
        menu.addItem(.separator())
        menu.addItem(item("修改…") { [weak self] in
            self?.onOpen?()
        })

        menu.popUp(positioning: nil,
                   at: NSPoint(x: menuButton.frame.minX, y: menuButton.frame.minY - 2),
                   in: self)
    }

    private func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let entry = ClosureMenuItem(title: title, handler: action)
        entry.target = entry
        entry.action = #selector(ClosureMenuItem.fire)
        return entry
    }

    static func tonight() -> Date {
        let calendar = Calendar.current
        let base = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
        if base > Date() { return base }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) else { return base }
        return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: tomorrow) ?? base
    }
}

// MARK: - 带闭包的菜单项

final class ClosureMenuItem: NSMenuItem {

    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: nil, keyEquivalent: "")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc func fire() { handler() }
}

// MARK: - 颜色

extension ReminderKind {
    var tint: NSColor {
        switch self {
        case .moment: return .systemBlue
        case .deadline: return .systemOrange
        case .recurring: return .systemPurple
        case .pool: return .systemGreen
        }
    }
}
