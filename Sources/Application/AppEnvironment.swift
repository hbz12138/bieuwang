// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import Foundation

// MARK: - 组装
//
// 全 App 只有这一个地方知道"谁依赖谁"。想换一个日历实现、换一个存储方式，
// 改这里的一行就行，Domain 和 UI 都不用动。

final class AppEnvironment {

    let document: JSONDocumentFile
    let calendar: EventKitCalendarSync
    let notifier: SystemNotifier
    let library: ReminderLibrary
    let engine: SchedulingEngine

    init(directory: URL) {
        self.document = JSONDocumentFile(directory: directory)
        self.calendar = EventKitCalendarSync(calendarName: "别忘")
        self.notifier = SystemNotifier()

        self.library = ReminderLibrary(
            document: document,
            calendar: calendar,
            notifier: notifier
        )

        self.engine = SchedulingEngine(
            library: library,
            notifier: notifier
        )
    }

    func bootstrap() {
        notifier.register()

        calendar.requestAccess { [weak self] granted in
            guard let self else { return }
            NSLog("[别忘] 日历同步：\(granted ? "已开启" : "未授权")")
            if granted {
                self.library.repairCalendarLinks()
            }
        }

        engine.start()
    }

    func shutdown() {
        engine.stop()
        library.saveNow()
    }
}
