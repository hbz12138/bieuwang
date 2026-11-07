// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import Foundation

// MARK: - 什么时候该响
//
// 纯函数：给一条提醒和"现在"，算出下一次该响的时刻。没有副作用。

enum ScheduleRule {

    /// 返回的可能是**过去的时间**：那是"错过了、该补课"。
    /// 引擎看到 fireAt <= now 就会立刻响一次。
    static func nextFire(for reminder: Reminder, after now: Date, settings: Settings) -> Date? {
        guard reminder.status == .active else { return nil }

        if let snoozed = reminder.snoozedUntil, snoozed > now {
            return snoozed
        }

        switch reminder.kind {
        case .pool:
            return nil

        case .moment:
            guard let due = reminder.dueAt else { return nil }
            let nags = settings.nagEnabled ? settings.nagOffsets : []
            let slots = [due] + nags.map { due.addingTimeInterval($0) }
            guard reminder.fireCount < slots.count else { return nil }
            return slots[reminder.fireCount]

        case .deadline:
            guard let deadline = reminder.deadlineAt else { return nil }
            guard reminder.stageIndex < settings.deadlineOffsets.count else { return nil }
            return deadline.addingTimeInterval(settings.deadlineOffsets[reminder.stageIndex])

        case .recurring:
            return reminder.dueAt
        }
    }

    /// 这一次是不是"你自己定的那个点"（而不是事后追的提醒）
    static func isPrimaryOccurrence(_ reminder: Reminder, settings: Settings) -> Bool {
        switch reminder.kind {
        case .moment:
            return reminder.fireCount == 0
        case .deadline:
            // 最后一档就是"到点"，前面几档是提前预警
            return reminder.stageIndex >= settings.deadlineOffsets.count - 1
        case .recurring:
            return true
        case .pool:
            return false
        }
    }

    static func isOverdue(_ reminder: Reminder, now: Date) -> Bool {
        guard reminder.status == .active else { return false }
        guard let date = reminder.kind == .deadline ? reminder.deadlineAt : reminder.dueAt else { return false }
        return date < now
    }

    /// 下一次响的"说明文字"，用在通知副标题上
    static func subtitle(for reminder: Reminder, at fireDate: Date) -> String {
        switch reminder.kind {
        case .deadline:
            guard let deadline = reminder.deadlineAt else { return "截止提醒" }
            let left = deadline.timeIntervalSince(fireDate)
            if left <= 0 { return "已经到期" }
            let hours = Int(left / 3600)
            if hours >= 24 { return "还有 \(hours / 24) 天到期" }
            if hours >= 1 { return "还有 \(hours) 小时到期" }
            return "还有 \(max(1, Int(left / 60))) 分钟到期"
        case .recurring:
            return reminder.recurrence?.summary ?? "重复提醒"
        case .pool:
            return "待办池里的一件"
        case .moment:
            return RelativeDay.label(for: fireDate) + " " + RelativeDay.time(fireDate)
        }
    }

    /// 截止类为了在日历里实现"逐级加强"，需要把档位换算成相对事件开始的分钟数
    static func calendarAlarmOffsets(for reminder: Reminder, settings: Settings) -> [TimeInterval] {
        switch reminder.kind {
        case .deadline:
            return settings.deadlineOffsets.filter { $0 <= 0 }
        case .moment:
            return [0]
        case .recurring:
            return [0]
        case .pool:
            return []
        }
    }
}

// MARK: - 重复规则的下一次

enum RecurrenceEngine {
    static func next(after now: Date, rule: Recurrence, calendar: Calendar = .current) -> Date? {
        var comps = DateComponents()
        comps.hour = rule.hour
        comps.minute = rule.minute
        comps.second = 0

        switch rule.freq {
        case .daily:
            return calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)

        case .weekdays:
            var cursor = now
            for _ in 0..<14 {
                guard let candidate = calendar.nextDate(after: cursor, matching: comps, matchingPolicy: .nextTime) else { return nil }
                let weekday = calendar.component(.weekday, from: candidate)
                if weekday != 1 && weekday != 7 { return candidate }
                cursor = candidate
            }
            return nil

        case .weekly:
            comps.weekday = rule.weekday ?? 2
            return calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)

        case .monthly:
            comps.day = rule.monthDay ?? 1
            return calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
        }
    }
}
