// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import AppKit
import UserNotifications
import ServiceManagement
import Combine

// MARK: - 记住数据放在哪
//
// 数据是一个可以随便搬的 JSON；这个指针文件只记住它在哪。
// 你把「别忘」文件夹拖到别处，在设置里指一下就行。

enum AppPaths {

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("别忘", isDirectory: true)
    }

    static var pointerFile: URL { supportDirectory.appendingPathComponent("location.txt") }

    static func readLocation() -> URL? {
        guard let text = try? String(contentsOf: pointerFile, encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func writeLocation(_ url: URL) {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try? url.path.write(to: pointerFile, atomically: true, encoding: .utf8)
    }
}

// MARK: - 登录时启动

enum LaunchAtLogin {

    static func set(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                NSLog("[别忘] 登录项设置失败：\(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 菜单栏

final class MenuBarController: NSObject, UNUserNotificationCenterDelegate {

    private let environment: AppEnvironment
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var storeWatcher: AnyCancellable?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func install() {
        setupStatusItem()
        setupPopover()

        UNUserNotificationCenter.current().delegate = self
        environment.bootstrap()

        storeWatcher = environment.library.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshBadge() }
        }

        if environment.library.settings.launchAtLogin {
            LaunchAtLogin.set(true)
        }
    }

    func shutdown() {
        environment.shutdown()
    }

    // MARK: 菜单栏图标

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "别忘")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover(_:))
        refreshBadge()
    }

    private func refreshBadge() {
        guard let button = statusItem?.button else { return }
        let overdue = environment.library.overdueCount

        button.title = overdue > 0 ? " \(overdue)" : ""
        button.image = NSImage(
            systemSymbolName: overdue > 0 ? "bell.badge" : "checklist",
            accessibilityDescription: "别忘"
        )
        button.image?.isTemplate = true
        button.toolTip = overdue > 0 ? "别忘：有 \(overdue) 件已过期" : "别忘"
    }

    // MARK: 面板

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = PopoverController(library: environment.library)
        popover.contentSize = NSSize(width: 400, height: 560)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        NSApp.activate(ignoringOtherApps: true)

        // 激活是异步的：立刻 show 会让弹窗在"应用还没变成前台"时就建好窗口，
        // 结果窗口不是 key —— 打字打不进去、第一次点击被吞掉。
        // 放到下一轮 runloop 再 show，并主动把焦点交给输入框。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            guard let window = self.popover.contentViewController?.view.window else { return }
            if let panel = window as? NSPanel { panel.becomesKeyOnlyIfNeeded = false }
            window.makeKeyAndOrderFront(nil)
            (self.popover.contentViewController as? PopoverController)?.focusQuickAdd()
        }
    }

    private func showPopoverIfPossible() {
        guard !popover.isShown, let button = statusItem.button else { return }
        showPopover(relativeTo: button)
    }

    // MARK: 通知交互

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }

        let info = response.notification.request.content.userInfo
        guard let raw = info["id"] as? String, let id = UUID(uuidString: raw) else { return }

        let library = environment.library
        switch response.actionIdentifier {
        case SystemNotifier.actionSnooze10:
            library.snooze(id: id, until: Date().addingTimeInterval(10 * 60))
        case SystemNotifier.actionSnooze60:
            library.snooze(id: id, until: Date().addingTimeInterval(60 * 60))
        case SystemNotifier.actionTonight:
            library.snooze(id: id, until: tonight())
        case SystemNotifier.actionDone:
            library.complete(id: id)
        default:
            showPopoverIfPossible()
        }
    }

    private func tonight() -> Date {
        let calendar = Calendar.current
        let base = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
        if base > Date() { return base }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) else { return base }
        return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: tomorrow) ?? base
    }
}
