// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import Foundation
import UserNotifications

// MARK: - 系统通知
//
// 这是 ReminderNotifying 的实现。日历那边已经在管"准点响"，
// 这里负责"现在就叫你、并且给你一键推迟的按钮"。

final class SystemNotifier: ReminderNotifying {

    static let categoryID = "BIEWANG_REMIND"
    static let actionSnooze10 = "SNOOZE_10"
    static let actionSnooze60 = "SNOOZE_60"
    static let actionTonight = "SNOOZE_TONIGHT"
    static let actionDone = "DONE"

    func register() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { NSLog("[别忘] 通知授权失败：\(error.localizedDescription)") }
            NSLog("[别忘] 通知权限：\(granted)")
        }

        let actions: [UNNotificationAction] = [
            UNNotificationAction(identifier: Self.actionSnooze10, title: "10 分钟后", options: []),
            UNNotificationAction(identifier: Self.actionSnooze60, title: "1 小时后", options: []),
            UNNotificationAction(identifier: Self.actionTonight, title: "今晚再说", options: []),
            UNNotificationAction(identifier: Self.actionDone, title: "完成了", options: [])
        ]

        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func post(_ reminder: Reminder, at fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.subtitle = ScheduleRule.subtitle(for: reminder, at: fireDate)
        content.body = reminder.note.isEmpty ? "该处理了。" : reminder.note
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["id": reminder.id.uuidString]

        deliver(content, key: "\(reminder.id.uuidString)-\(Int(fireDate.timeIntervalSince1970))")
    }

    func postPoolPick(_ reminder: Reminder) {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.subtitle = "待办池里的一件"
        content.body = "现在处理，还是再放放？"
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["id": reminder.id.uuidString]

        deliver(content, key: "pool-\(reminder.id.uuidString)-\(Int(Date().timeIntervalSince1970))")
    }

    private func deliver(_ content: UNMutableNotificationContent, key: String) {
        let request = UNNotificationRequest(
            identifier: key,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("[别忘] 通知发送失败：\(error.localizedDescription)") }
        }
    }
}
