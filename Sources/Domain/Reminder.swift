// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import Foundation

// MARK: - 一条提醒是什么
//
// 这一层只描述"数据长什么样"，不关心它怎么被存、怎么被响、怎么被显示。

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    /// 某个时间点做一件事
    case moment
    /// 某天之前要完成
    case deadline
    /// 每天 / 每周固定要做
    case recurring
    /// 没有时间，放在池子里等被抽到
    case pool

    var id: String { rawValue }

    var label: String {
        switch self {
        case .moment: return "定时"
        case .deadline: return "截止"
        case .recurring: return "重复"
        case .pool: return "待办"
        }
    }

    var symbol: String {
        switch self {
        case .moment: return "clock"
        case .deadline: return "flag"
        case .recurring: return "arrow.triangle.2.circlepath"
        case .pool: return "tray"
        }
    }

    var hint: String {
        switch self {
        case .moment: return "几点做什么，到点响一声"
        case .deadline: return "某天之前要完成，提前几天就开始提醒"
        case .recurring: return "每天/每周固定要做，这一期没做不影响下一期"
        case .pool: return "没有时间，放在池子里，空闲时一次抽一件"
        }
    }

    /// 这类提醒是否需要写进系统日历
    var writesToCalendar: Bool { self != .pool }
}

enum ReminderStatus: String, Codable {
    case active, done, dropped
}

enum RepeatFreq: String, Codable, CaseIterable, Identifiable {
    case daily, weekdays, weekly, monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "每天"
        case .weekdays: return "每个工作日"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }
}

struct Recurrence: Codable, Hashable {
    var freq: RepeatFreq
    var hour: Int
    var minute: Int
    /// Calendar 的 weekday：1 = 周日，7 = 周六
    var weekday: Int?
    var monthDay: Int?

    var timeText: String { String(format: "%02d:%02d", hour, minute) }

    var summary: String {
        switch freq {
        case .daily: return "每天 \(timeText)"
        case .weekdays: return "工作日 \(timeText)"
        case .weekly:
            let names = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return "每\(names[max(1, min(7, weekday ?? 2))]) \(timeText)"
        case .monthly:
            return "每月 \(monthDay ?? 1) 日 \(timeText)"
        }
    }
}

// MARK: - 提醒本体

struct Reminder: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var note: String = ""
    var kind: ReminderKind

    /// 定时 / 重复 的下一个触发时刻
    var dueAt: Date?
    /// 截止类的时间点
    var deadlineAt: Date?
    var recurrence: Recurrence?

    var status: ReminderStatus = .active
    var createdAt: Date = Date()
    var completedAt: Date?
    var droppedAt: Date?

    /// 点「稍后」后压到这个时间再说（只影响本 App 的提醒，不挪日历）
    var snoozedUntil: Date?
    /// 上一次真正响过的时间
    var lastFiredAt: Date?
    var fireCount: Int = 0
    /// 截止类走到第几档
    var stageIndex: Int = 0
    /// 重复类：本次待办的那一期
    var pendingOccurrence: Date?
    /// 待办池：上次被抽问的时间
    var nudgedAt: Date?
    /// 已经写进系统日历的那个事件
    var calendarEventID: String?

    var isActive: Bool { status == .active }

    /// 决定"哪天"的那个时间（用于分组和排序）
    var primaryDate: Date? {
        switch kind {
        case .deadline: return deadlineAt
        case .pool: return nil
        default: return dueAt
        }
    }
}

// MARK: - 小工具

enum ClockText {
    static func parse(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    static func date(from base: Date, hour: Int, minute: Int) -> Date? {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: base)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps)
    }
}

enum RelativeDay {
    static func isToday(_ d: Date) -> Bool {
        Calendar.current.isDate(d, inSameDayAs: Date())
    }

    static func isTomorrow(_ d: Date) -> Bool {
        guard let t = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return false }
        return Calendar.current.isDate(d, inSameDayAs: t)
    }

    static func label(for d: Date) -> String {
        if isToday(d) { return "今天" }
        if isTomorrow(d) { return "明天" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M月d日"
        return df.string(from: d)
    }

    static func time(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "HH:mm"
        return df.string(from: d)
    }
}
