// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import Foundation
import EventKit

// MARK: - 日历同步（EventKit → iCloud 日历）
//
// 这是 CalendarSyncing 的一种实现。它把每条提醒写成系统日历里的一个真实事件，
// 于是 iCloud 会自动把它同步到 iPhone / iPad / 另一台 Mac，
// 系统日历也会替你响——App 关着也响。
//
// 想换成 Google 日历、Outlook、或者别的渠道：再写一个符合 CalendarSyncing 的类，别的都不用改。

final class EventKitCalendarSync: CalendarSyncing {

    private let store = EKEventStore()
    private var cachedCalendar: EKCalendar?
    private let calendarName: String

    private(set) var isAvailable: Bool = false

    init(calendarName: String) {
        self.calendarName = calendarName
    }

    // MARK: 权限

    func requestAccess(completion: @escaping (Bool) -> Void) {
        let current = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            if current == .fullAccess {
                isAvailable = true
                completion(true)
                return
            }
            store.requestFullAccessToEvents { granted, error in
                if let error { NSLog("[别忘] 日历授权失败：\(error.localizedDescription)") }
                self.isAvailable = granted
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            if current == .authorized {
                isAvailable = true
                completion(true)
                return
            }
            store.requestAccess(to: .event) { granted, error in
                if let error { NSLog("[别忘] 日历授权失败：\(error.localizedDescription)") }
                self.isAvailable = granted
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    func refreshAvailability() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            isAvailable = (status == .fullAccess)
        } else {
            isAvailable = (status == .authorized)
        }
    }

    // MARK: 找到 / 建好「别忘」日历

    private func ensureCalendar() -> EKCalendar? {
        if let cached = cachedCalendar { return cached }

        let all = store.calendars(for: .event)
        if let existing = all.first(where: { $0.title == calendarName }) {
            cachedCalendar = existing
            return existing
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarName

        // 优先挂在 iCloud（或其它 CalDAV 账户）下，这样手机才收得到
        let sources = store.sources
        let preferred = sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("iCloud") }
            ?? sources.first { $0.sourceType == .calDAV }
            ?? sources.first { $0.sourceType == .local }
            ?? sources.first

        guard let source = preferred else {
            NSLog("[别忘] 找不到可用的日历账户")
            return nil
        }
        calendar.source = source

        do {
            try store.saveCalendar(calendar, commit: true)
            cachedCalendar = calendar
            return calendar
        } catch {
            NSLog("[别忘] 创建日历失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: 写入

    func apply(_ reminder: Reminder, alarmOffsets: [TimeInterval]) throws -> String? {
        guard isAvailable, let start = reminder.primaryDate else { return reminder.calendarEventID }
        guard let calendar = ensureCalendar() else { return reminder.calendarEventID }

        let event: EKEvent
        if let id = reminder.calendarEventID, let existing = store.event(withIdentifier: id) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
        }

        event.calendar = calendar
        event.title = reminder.title
        event.notes = reminder.note
        event.startDate = start
        event.endDate = start.addingTimeInterval(30 * 60)
        event.isAllDay = false

        event.alarms = nil
        for offset in alarmOffsets {
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }

        if reminder.kind == .recurring, let rule = reminder.recurrence {
            event.recurrenceRules = [makeRule(rule)]
        } else {
            event.recurrenceRules = nil
        }

        try store.save(event, span: .futureEvents, commit: true)
        return event.eventIdentifier
    }

    func remove(_ reminder: Reminder) {
        guard let id = reminder.calendarEventID,
              let event = store.event(withIdentifier: id) else { return }
        do {
            try store.remove(event, span: .futureEvents, commit: true)
        } catch {
            NSLog("[别忘] 删除日历事件失败：\(error.localizedDescription)")
        }
    }

    func exists(_ eventID: String) -> Bool {
        store.event(withIdentifier: eventID) != nil
    }

    // MARK: 重复规则

    private func makeRule(_ rule: Recurrence) -> EKRecurrenceRule {
        switch rule.freq {
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)

        case .weekdays:
            let days = [2, 3, 4, 5, 6].map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0) ?? .monday) }
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: days,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )

        case .weekly:
            let day = EKRecurrenceDayOfWeek(EKWeekday(rawValue: rule.weekday ?? 2) ?? .monday)
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: [day],
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )

        case .monthly:
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: 1,
                daysOfTheWeek: nil,
                daysOfTheMonth: [NSNumber(value: rule.monthDay ?? 1)],
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )
        }
    }
}
