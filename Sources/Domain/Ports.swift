// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import Foundation

// MARK: - 端口（依赖倒置）
//
// Domain 只认识这些协议，不认识 EventKit、UNUserNotificationCenter、文件系统。
// 想换一种日历、换一种通知方式，只要新写一个实现，这一层不用动。

/// 把一条提醒落到某个外部日历上
protocol CalendarSyncing: AnyObject {
    var isAvailable: Bool { get }

    /// 新建或更新；成功时返回外部事件 id。
    /// 「提前几档提醒」是业务规则，由调用方算好再传进来，适配器不需要懂。
    func apply(_ reminder: Reminder, alarmOffsets: [TimeInterval]) throws -> String?

    /// 从外部日历里删掉
    func remove(_ reminder: Reminder)

    /// 外部日历里那条事件是否还在（被用户手动删掉时需要知道）
    func exists(_ eventID: String) -> Bool
}

/// 发一条系统通知
protocol ReminderNotifying: AnyObject {
    func post(_ reminder: Reminder, at fireDate: Date)
    func postPoolPick(_ reminder: Reminder)
}

/// 读写整份数据
protocol DocumentPersisting: AnyObject {
    var fileURL: URL { get }
    func load() throws -> ReminderDocument?
    func save(_ document: ReminderDocument) throws
    func relocate(to directory: URL) throws
}

// MARK: - 配置

struct Settings: Codable {
    var dataDirectory: String
    /// 首次响过之后继续追的间隔（秒）
    var nagOffsets: [TimeInterval] = [15 * 60, 60 * 60]
    /// 截止类的提前档位（秒）：提前 3 天、1 天、2 小时、到点
    var deadlineOffsets: [TimeInterval] = [-3 * 86400, -1 * 86400, -2 * 3600, 0]
    /// 待办池每天被抽问的时刻
    var idleNudgeTimes: [String] = ["10:00", "15:00", "20:00"]
    var quietFrom: String = "23:00"
    var quietTo: String = "07:30"

    var nagEnabled: Bool = true
    var launchAtLogin: Bool = true
    /// 是否写进系统日历
    var calendarSyncEnabled: Bool = true
    /// 用哪个日历承载（默认新建一个叫「别忘」的）
    var calendarName: String = "别忘"

    static func defaultDirectory() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return docs.appendingPathComponent("别忘", isDirectory: true).path
    }
}

struct ReminderDocument: Codable {
    var version: Int = 2
    var settings: Settings
    var reminders: [Reminder]

    static func empty(at directory: String) -> ReminderDocument {
        ReminderDocument(settings: Settings(dataDirectory: directory), reminders: [])
    }
}

// MARK: - JSON 编解码（固定策略，避免各处不一致）

extension JSONEncoder {
    static var bieuwang: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

extension JSONDecoder {
    static var bieuwang: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
