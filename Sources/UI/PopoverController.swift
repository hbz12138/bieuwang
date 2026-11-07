// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import AppKit
import Combine

// MARK: - 面板（AppKit 手写，无 SwiftUI 依赖）

final class PopoverController: NSViewController {

    private let library: ReminderLibrary
    private var cancellables: Set<AnyCancellable> = []

    private var tab: MainTab = .today
    private var now = Date()

    private let segmented = NSSegmentedControl()
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let kindPopup = NSPopUpButton()
    private let titleField = NSTextField()
    private let overdueBadge = NSTextField(labelWithString: "")
    private let clock = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    private var clockCancel: AnyCancellable?
    private var lastRenderKey: String = ""
    private let hintLabel = NSTextField(labelWithString: "")
    /// 强引用住正在显示的表单/设置窗口控制器（否则按钮的 target 会被释放）
    private var retainedPresenters: [AnyObject] = []

    init(library: ReminderLibrary) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 400, height: 560)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 560))
        root.wantsLayer = true
        view = root

        let header = buildHeader()
        let quickAdd = buildQuickAdd()
        let tabs = buildTabs()
        let footer = buildFooter()

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        scrollView.documentView = document

        let sep1 = separator()
        let sep2 = separator()
        let sep3 = separator()
        let sep4 = separator()

        for sub in [header, sep1, quickAdd, sep2, tabs, sep3, scrollView, sep4, footer] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(sub)
        }

        document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true

        for line in [sep1, sep2, sep3, sep4] {
            line.leadingAnchor.constraint(equalTo: root.leadingAnchor).isActive = true
            line.trailingAnchor.constraint(equalTo: root.trailingAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            sep1.topAnchor.constraint(equalTo: header.bottomAnchor),
            sep1.heightAnchor.constraint(equalToConstant: 1),

            quickAdd.topAnchor.constraint(equalTo: sep1.bottomAnchor),
            quickAdd.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            quickAdd.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            quickAdd.heightAnchor.constraint(equalToConstant: 46),

            sep2.topAnchor.constraint(equalTo: quickAdd.bottomAnchor),
            sep2.heightAnchor.constraint(equalToConstant: 1),

            tabs.topAnchor.constraint(equalTo: sep2.bottomAnchor),
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabs.heightAnchor.constraint(equalToConstant: 52),

            sep3.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            sep3.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: sep3.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sep4.topAnchor),

            sep4.bottomAnchor.constraint(equalTo: footer.topAnchor),
            sep4.heightAnchor.constraint(equalToConstant: 1),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 29)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        library.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        reload()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        lastRenderKey = ""
        reload()
        clockCancel = clock.sink { [weak self] date in
            self?.now = date
            self?.reload()
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        clockCancel?.cancel()
        clockCancel = nil
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // 双保险：有些路径下弹窗建好时窗口还不是 key，
        // 那样打字进不去、第一次点击也会被吞掉。
        view.window?.makeKeyAndOrderFront(nil)
        view.window?.makeFirstResponder(titleField)
    }

    // MARK: 头部

    private func buildHeader() -> NSView {
        let container = NSView()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "别忘")
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "别忘")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        overdueBadge.font = .systemFont(ofSize: 10, weight: .bold)
        overdueBadge.textColor = .white
        overdueBadge.wantsLayer = true
        overdueBadge.layer?.backgroundColor = NSColor.systemRed.cgColor
        overdueBadge.layer?.cornerRadius = 7
        overdueBadge.alignment = .center
        overdueBadge.translatesAutoresizingMaskIntoConstraints = false

        let gear = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")!,
                            target: self, action: #selector(openSettings))
        gear.isBordered = false
        gear.translatesAutoresizingMaskIntoConstraints = false

        let quit = NSButton(image: NSImage(systemSymbolName: "power", accessibilityDescription: "退出")!,
                            target: self, action: #selector(quit))
        quit.isBordered = false
        quit.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(title)
        container.addSubview(overdueBadge)
        container.addSubview(gear)
        container.addSubview(quit)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            title.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            overdueBadge.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 6),
            overdueBadge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            overdueBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            overdueBadge.heightAnchor.constraint(equalToConstant: 14),

            quit.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            quit.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            quit.widthAnchor.constraint(equalToConstant: 20),

            gear.trailingAnchor.constraint(equalTo: quit.leadingAnchor, constant: -10),
            gear.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            gear.widthAnchor.constraint(equalToConstant: 20)
        ])
        return container
    }

    // MARK: 快速添加

    private func buildQuickAdd() -> NSView {
        let container = NSView()

        kindPopup.translatesAutoresizingMaskIntoConstraints = false
        kindPopup.addItems(withTitles: ReminderKind.allCases.map { $0.label })
        kindPopup.target = self
        kindPopup.action = #selector(kindChanged)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.placeholderString = "想到什么就写一句…"
        titleField.font = .systemFont(ofSize: 13)
        titleField.target = self
        titleField.action = #selector(commitDraft)

        let add = NSButton(image: NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "添加")!,
                           target: self, action: #selector(commitDraft))
        add.isBordered = false
        add.translatesAutoresizingMaskIntoConstraints = false

        let detail = NSButton(image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "详细")!,
                              target: self, action: #selector(openNewEditor))
        detail.isBordered = false
        detail.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(kindPopup)
        container.addSubview(titleField)
        container.addSubview(add)
        container.addSubview(detail)

        NSLayoutConstraint.activate([
            kindPopup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            kindPopup.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            kindPopup.widthAnchor.constraint(equalToConstant: 76),

            titleField.leadingAnchor.constraint(equalTo: kindPopup.trailingAnchor, constant: 8),
            titleField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleField.heightAnchor.constraint(equalToConstant: 24),

            add.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 6),
            add.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            add.widthAnchor.constraint(equalToConstant: 22),

            detail.leadingAnchor.constraint(equalTo: add.trailingAnchor, constant: 6),
            detail.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            detail.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            detail.widthAnchor.constraint(equalToConstant: 18)
        ])
        return container
    }

    // MARK: 分栏

    private func buildTabs() -> NSView {
        let container = NSView()

        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.segmentCount = MainTab.allCases.count
        segmented.segmentStyle = .automatic
        segmented.trackingMode = .selectOne
        segmented.selectedSegment = 0
        segmented.target = self
        segmented.action = #selector(tabChanged)
        for (index, item) in MainTab.allCases.enumerated() {
            segmented.setLabel(item.title, forSegment: index)
        }

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail

        container.addSubview(segmented)
        container.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            segmented.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            segmented.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            segmented.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            segmented.heightAnchor.constraint(equalToConstant: 24),

            hintLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            hintLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            hintLabel.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 3)
        ])
        return container
    }

    // MARK: 底部

    private func buildFooter() -> NSView {
        let container = NSView()

        let path = NSTextField(labelWithString: "")
        path.font = .systemFont(ofSize: 10)
        path.textColor = .tertiaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle
        path.translatesAutoresizingMaskIntoConstraints = false
        path.identifier = NSUserInterfaceItemIdentifier("pathLabel")

        let reveal = NSButton(title: "打开数据文件夹", target: self, action: #selector(revealData))
        reveal.isBordered = false
        reveal.font = .systemFont(ofSize: 10)
        reveal.contentTintColor = .secondaryLabelColor
        reveal.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(path)
        container.addSubview(reveal)

        NSLayoutConstraint.activate([
            path.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            path.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            path.trailingAnchor.constraint(lessThanOrEqualTo: reveal.leadingAnchor, constant: -8),

            reveal.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            reveal.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func separator() -> NSView {
        let line = NSView()
        line.identifier = NSUserInterfaceItemIdentifier("sep")
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    // MARK: 刷新

    func reload() {
        now = Date()
        updateHeader()
        updateTabs()

        let incoming = currentItems()
        let key = renderKey(for: incoming)
        if key == lastRenderKey { return }
        lastRenderKey = key

        for sub in stack.arrangedSubviews {
            stack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        let items = incoming
        if items.isEmpty {
            let empty = NSTextField(labelWithString: emptyText())
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            let holder = NSView()
            holder.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
                empty.topAnchor.constraint(equalTo: holder.topAnchor, constant: 60),
                holder.heightAnchor.constraint(equalToConstant: 140)
            ])
            stack.addArrangedSubview(holder)
            holder.translatesAutoresizingMaskIntoConstraints = false
            holder.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        } else {
            for item in items {
                let row = ReminderRowView(
                    reminder: item,
                    now: now,
                    library: library,
                    onOpen: { [weak self] in self?.openEditor(for: item) },
                    onDelete: { [weak self] in self?.confirmDelete(item) }
                )
                row.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(row)
                row.heightAnchor.constraint(equalToConstant: 54).isActive = true
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }

        if let pathLabel = view.subviews
            .compactMap({ $0.subviews.first(where: { $0.identifier?.rawValue == "pathLabel" }) })
            .first as? NSTextField {
            pathLabel.stringValue = library.fileURL.deletingLastPathComponent().lastPathComponent
            pathLabel.toolTip = library.fileURL.path
        }
    }

    /// 只有"看得见的东西"变了才重建列表，避免每 20 秒白白重建一遍
    private func renderKey(for items: [Reminder]) -> String {
        var parts: [String] = [tab.rawValue]
        for item in items {
            let overdue = ScheduleRule.isOverdue(item, now: now)
            parts.append("\(item.id.uuidString):\(item.hashValue):\(overdue)")
        }
        return parts.joined(separator: "|")
    }

    private func currentItems() -> [Reminder] {
        switch tab {
        case .today: return library.todayList(now: now)
        case .pool: return library.poolList()
        case .later: return library.upcomingList(now: now)
        case .done: return library.doneList()
        }
    }

    private func updateHeader() {
        let count = library.overdueCount
        overdueBadge.stringValue = count > 0 ? " \(count) " : ""
        overdueBadge.isHidden = count == 0
    }

    /// 每个分栏到底是干什么的，直接写在下面，不让人猜
    private func hint(for tab: MainTab) -> String {
        switch tab {
        case .today: return "今天到点的，加上已经过期的（红色）"
        case .pool: return "没定时间的事，每天空闲时抽一件问你"
        case .later: return "明天及以后"
        case .done: return "已完成 / 已放弃，点左边圆点可以恢复"
        }
    }

    private func updateTabs() {
        hintLabel.stringValue = hint(for: tab)
        for (index, item) in MainTab.allCases.enumerated() {
            var text = item.title
            switch item {
            case .today:
                let n = library.todayList(now: now).count
                text = n > 0 ? "今天 \(n)" : "今天"
            case .pool:
                let n = library.poolList().count
                text = n > 0 ? "待办池 \(n)" : "待办池"
            default:
                break
            }
            segmented.setLabel(text, forSegment: index)
        }
    }

    private func emptyText() -> String {
        switch tab {
        case .today: return "今天没有要紧的事"
        case .pool: return "池子是空的"
        case .later: return "以后还没有安排"
        case .done: return "还没有记录"
        }
    }

    // MARK: 动作

    @objc private func tabChanged() {
        let index = segmented.selectedSegment
        tab = MainTab.allCases[max(0, min(MainTab.allCases.count - 1, index))]
        reload()
    }

    @objc private func kindChanged() {
        // 占位：类型只影响"详细"窗口的默认值
    }

    private var selectedKind: ReminderKind {
        let index = kindPopup.indexOfSelectedItem
        return ReminderKind.allCases[max(0, min(ReminderKind.allCases.count - 1, index))]
    }

    @objc private func commitDraft() {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            // 空着点＋不该"没反应"：给个声音，并把光标放回输入框
            NSSound.beep()
            view.window?.makeFirstResponder(titleField)
            return
        }
        let item = QuickAdd.make(title: title, kind: selectedKind)
        library.upsert(item)
        titleField.stringValue = ""
        reveal(item)
    }

    /// 加完之后，把分栏切到"它真正在的地方"。
    /// 否则 23:30 加一条「1 小时后」的事，它落在明天、进了「之后」，
    /// 而你盯着「今天」——看起来就像根本没加上。
    private func reveal(_ reminder: Reminder) {
        let target: MainTab
        if reminder.kind == .pool {
            target = .pool
        } else if let date = reminder.primaryDate,
                  RelativeDay.isToday(date) || ScheduleRule.isOverdue(reminder, now: Date()) {
            target = .today
        } else {
            target = .later
        }

        tab = target
        if let index = MainTab.allCases.firstIndex(of: target) {
            segmented.selectedSegment = index
        }
        lastRenderKey = ""
        reload()
    }

    @objc private func openNewEditor() {
        var created: EditorController?
        let editor = EditorController(library: library, existing: nil,
                                      defaultKind: selectedKind) { [weak self] in
            guard let self else { return }
            if let saved = created?.lastSaved {
                self.reveal(saved)
            } else {
                self.reload()
            }
        }
        created = editor
        retain(editor)
        editor.present(asSheetOf: view.window)
    }

    private func openEditor(for reminder: Reminder) {
        var created: EditorController?
        let editor = EditorController(library: library, existing: reminder,
                                      defaultKind: reminder.kind) { [weak self] in
            guard let self else { return }
            if let saved = created?.lastSaved {
                self.reveal(saved)
            } else {
                self.reload()
            }
        }
        created = editor
        retain(editor)
        editor.present(asSheetOf: view.window)
    }

    /// 彻底删除要二次确认，因为它是唯一不可撤销的动作
    private func confirmDelete(_ reminder: Reminder) {
        let alert = NSAlert()
        alert.messageText = "彻底删除「\(reminder.title)」？"
        alert.informativeText = "它会从记录里消失，无法恢复。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")

        if let window = view.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.library.delete(id: reminder.id)
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            library.delete(id: reminder.id)
        }
    }

    @objc private func openSettings() {
        let settings = SettingsController(library: library) { [weak self] in self?.reload() }
        retain(settings)
        settings.present(asSheetOf: view.window)
    }

    @objc private func revealData() {
        NSWorkspace.shared.activateFileViewerSelecting([library.fileURL])
    }

    // MARK: 弹窗生命周期

    /// 表单里的按钮把控制器自己当 target。如果控制器创建完就没人引用，
    /// 它会立刻被释放，按钮点下去就是"对着空气发消息"——这就是之前点不动的根因。
    private func retain(_ controller: AnyObject) {
        retainedPresenters.append(controller)
        if retainedPresenters.count > 4 {
            retainedPresenters.removeFirst()
        }
    }

    /// 让面板一打开光标就在输入框里，打完字直接回车
    func focusQuickAdd() {
        view.window?.makeFirstResponder(titleField)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - 分栏定义

enum MainTab: String, CaseIterable, Identifiable {
    case today, pool, later, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今天"
        case .pool: return "待办池"
        case .later: return "以后"
        case .done: return "记录"
        }
    }
}

// MARK: - 快速添加的默认值

enum QuickAdd {
    static func make(title: String, kind: ReminderKind) -> Reminder {
        var item = Reminder(title: title, kind: kind)
        switch kind {
        case .pool:
            break
        case .moment:
            item.dueAt = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
        case .deadline:
            item.deadlineAt = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        case .recurring:
            let rule = Recurrence(freq: .daily, hour: 9, minute: 0, weekday: nil, monthDay: nil)
            item.recurrence = rule
            item.dueAt = RecurrenceEngine.next(after: Date(), rule: rule)
        }
        return item
    }
}
