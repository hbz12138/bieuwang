// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import Foundation

// MARK: - 导出 .ics
//
// 给"这台电脑以外"兜底：导进任何日历 App 都行。
// 和 EventKit 同步不冲突——一个是持续同步，一个是一次性快照。

enum ICSExporter {

    static func export(_ reminders: [Reminder]) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Bieuwang//Reminder//CN",
            "CALSCALE:GREGORIAN"
        ]

        for reminder in reminders {
            guard let start = reminder.primaryDate else { continue }

            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(reminder.id.uuidString)")
            lines.append("DTSTAMP:\(df.string(from: Date()))")
            lines.append("DTSTART:\(df.string(from: start))")
            lines.append("DTEND:\(df.string(from: start.addingTimeInterval(1800)))")
            lines.append("SUMMARY:\(escape(reminder.title))")
            if !reminder.note.isEmpty {
                lines.append("DESCRIPTION:\(escape(reminder.note))")
            }

            if let rule = reminder.recurrence {
                lines.append("RRULE:" + rrule(rule))
            }

            for offset in alarmOffsets(for: reminder) {
                lines.append("BEGIN:VALARM")
                lines.append("TRIGGER:\(trigger(offset))")
                lines.append("ACTION:DISPLAY")
                lines.append("DESCRIPTION:\(escape(reminder.title))")
                lines.append("END:VALARM")
            }

            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    private static func alarmOffsets(for reminder: Reminder) -> [TimeInterval] {
        switch reminder.kind {
        case .deadline: return [-3 * 86400, -86400, -7200, 0]
        case .moment, .recurring: return [0]
        case .pool: return []
        }
    }

    private static func trigger(_ offset: TimeInterval) -> String {
        if offset == 0 { return "PT0S" }
        let minutes = Int(abs(offset) / 60)
        return offset < 0 ? "-PT\(minutes)M" : "PT\(minutes)M"
    }

    private static func rrule(_ rule: Recurrence) -> String {
        let until = "20401231T235959Z"
        switch rule.freq {
        case .daily:
            return "FREQ=DAILY;UNTIL=\(until)"
        case .weekdays:
            return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;UNTIL=\(until)"
        case .weekly:
            let map = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
            let index = max(1, min(7, rule.weekday ?? 2)) - 1
            return "FREQ=WEEKLY;BYDAY=\(map[index]);UNTIL=\(until)"
        case .monthly:
            return "FREQ=MONTHLY;BYMONTHDAY=\(rule.monthDay ?? 1);UNTIL=\(until)"
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
