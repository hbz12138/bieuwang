// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import AppKit

// MARK: - 入口

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let directory = resolveDataDirectory()
        let environment = AppEnvironment(directory: directory)
        let controller = MenuBarController(environment: environment)
        controller.install()
        self.controller = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    // MARK: 首次运行：让用户选数据放哪

    private func resolveDataDirectory() -> URL {
        if let existing = AppPaths.readLocation() {
            return existing
        }

        let fallback = URL(fileURLWithPath: Settings.defaultDirectory(), isDirectory: true)
        let fileManager = FileManager.default

        // 老数据还在原处就直接用，不打扰
        if fileManager.fileExists(atPath: fallback.appendingPathComponent("reminders.json").path) {
            try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            AppPaths.writeLocation(fallback)
            return fallback
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "用这个位置"
        panel.message = "选一个文件夹放「别忘」的数据。里面只有一个 reminders.json，你随时可以拷走它。"
        panel.directoryURL = fallback.deletingLastPathComponent()

        if panel.runModal() == .OK, let picked = panel.url {
            let target = picked.appendingPathComponent("别忘", isDirectory: true)
            try? fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            AppPaths.writeLocation(target)
            return target
        }

        try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        AppPaths.writeLocation(fallback)
        return fallback
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
