// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import Foundation
import Combine

// MARK: - 唯一的状态源 + 全部用例
//
// UI 只调这里的方法；这里只调三个协议。谁都不认识 EventKit。
// 想加"从日历反向导入""同步到 Google 日历"，在这个类里加方法即可。

final class ReminderLibrary: ObservableObject {

    @Published private(set) var reminders: [Reminder] = []
    @Published var settings: Settings

    private let document: DocumentPersisting
    private let calendar: CalendarSyncing
    private let notifier: ReminderNotifying

    private var saveWork: DispatchWorkItem?
    private var isSyncingCalendar = false

    init(document: DocumentPersisting,
         calendar: CalendarSyncing,
         notifier: ReminderNotifying) {
        self.document = document
        self.calendar = calendar
        self.notifier = notifier
        self.settings = Settings(dataDirectory: document.fileURL.deletingLastPathComponent().path)
        load()
    }

    var fileURL: URL { document.fileURL }

    // MARK: - 持久化

    func load() {
        do {
            if let doc = try document.load() {
                reminders = doc.reminders
                var s = doc.settings
                s.dataDirectory = document.fileURL.deletingLastPathComponent().path
                settings = s
            }
        } catch {
            NSLog("[别忘] 读取失败：\(error.localizedDescription)")
        }
    }

    func save() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func saveNow() {
        let doc = ReminderDocument(version: 2, settings: settings, reminders: reminders)
        do {
            try document.save(doc)
        } catch {
            NSLog("[别忘] 保存失败：\(error.localizedDescription)")
        }
    }

    func relocate(to directory: URL) {
        saveNow()
        do {
            try document.relocate(to: directory)
            settings.dataDirectory = directory.path
            load()
            saveNow()
        } catch {
            NSLog("[别忘] 迁移数据失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 查询

    func reminder(id: UUID) -> Reminder? { reminders.first { $0.id == id } }

    var active: [Reminder] { reminders.filter { $0.status == .active } }

    var overdueCount: Int {
        let now = Date()
        return active.filter { ScheduleRule.isOverdue($0, now: now) }.count
    }

    func todayList(now: Date = Date()) -> [Reminder] {
        sorted(active.filter {
            $0.kind != .pool && ($0.primaryDate.map { RelativeDay.isToday($0) } ?? false || ScheduleRule.isOverdue($0, now: now))
        })
    }

    func upcomingList(now: Date = Date()) -> [Reminder] {
        sorted(active.filter {
            guard $0.kind != .pool, let d = $0.primaryDate else { return false }
            return !RelativeDay.isToday(d) && !ScheduleRule.isOverdue($0, now: now)
        })
    }

    func poolList() -> [Reminder] {
        active.filter { $0.kind == .pool }.sorted { $0.createdAt < $1.createdAt }
    }

    func doneList() -> [Reminder] {
        reminders.filter { $0.status != .active }.sorted {
            ($0.completedAt ?? $0.droppedAt ?? $0.createdAt) > ($1.completedAt ?? $1.droppedAt ?? $1.createdAt)
        }
    }

    private func sorted(_ items: [Reminder]) -> [Reminder] {
        items.sorted { ($0.primaryDate ?? .distantFuture) < ($1.primaryDate ?? .distantFuture) }
    }

    // MARK: - 用例：新建 / 修改

    func upsert(_ reminder: Reminder) {
        var item = reminder
        if let index = reminders.firstIndex(where: { $0.id == item.id }) {
            item.calendarEventID = reminders[index].calendarEventID
            reminders[index] = item
        } else {
            reminders.append(item)
        }
        syncCalendar(for: item.id)
        save()
    }

    // MARK: - 用例：完成

    func complete(id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()

        if reminders[index].kind == .recurring, let rule = reminders[index].recurrence {
            // 重复类：完成的是"这一期"，下一期照常
            reminders[index].pendingOccurrence = nil
            reminders[index].dueAt = RecurrenceEngine.next(after: now, rule: rule)
            reminders[index].snoozedUntil = nil
            reminders[index].fireCount = 0
            reminders[index].lastFiredAt = nil
            syncCalendar(for: id)
        } else {
            reminders[index].status = .done
            reminders[index].completedAt = now
            reminders[index].snoozedUntil = nil
            removeFromCalendar(reminders[index])
        }
        save()
    }

    // MARK: - 用例：不做了

    /// 「不做了」= 我决定这件事不需要完成。
    /// 只对**还没结束**的提醒有效；已经完成/已放弃的不再被它改写，
    /// 否则会出现"点了不做了，完成记录里的划线消失"这种莫名其妙的现象。
    func drop(id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        guard reminders[index].status == .active else { return }

        if reminders[index].kind == .recurring,
           let rule = reminders[index].recurrence,
           reminders[index].pendingOccurrence != nil {
            // 只是跳过这一期
            reminders[index].pendingOccurrence = nil
            reminders[index].dueAt = RecurrenceEngine.next(after: Date(), rule: rule)
            reminders[index].snoozedUntil = nil
            reminders[index].fireCount = 0
            reminders[index].lastFiredAt = nil
            syncCalendar(for: id)
        } else {
            reminders[index].status = .dropped
            reminders[index].droppedAt = Date()
            reminders[index].snoozedUntil = nil
            removeFromCalendar(reminders[index])
        }
        save()
    }

    // MARK: - 用例：恢复（误点完成的那一下）

    /// 把「已完成 / 已放弃」的提醒拿回进行中。
    /// 这是给"手滑点了完成"准备的后悔药，一步到位，不用重新建一遍。
    func restore(id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        guard reminders[index].status != .active else { return }

        reminders[index].status = .active
        reminders[index].completedAt = nil
        reminders[index].droppedAt = nil
        reminders[index].snoozedUntil = nil

        // 恢复一条早就过期的事，让它从"现在"重新开始，
        // 而不是立刻标红、立刻响。
        switch reminders[index].kind {
        case .moment:
            if let due = reminders[index].dueAt, due < Date() {
                reminders[index].dueAt = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            }
            reminders[index].fireCount = 0
            reminders[index].lastFiredAt = nil
        case .deadline:
            if let deadline = reminders[index].deadlineAt, deadline < Date() {
                reminders[index].deadlineAt = Calendar.current.date(byAdding: .day, value: 1, to: Date())
            }
            reminders[index].stageIndex = 0
        case .recurring:
            if let rule = reminders[index].recurrence {
                reminders[index].dueAt = RecurrenceEngine.next(after: Date(), rule: rule)
            }
            reminders[index].fireCount = 0
            reminders[index].lastFiredAt = nil
        case .pool:
            break
        }

        syncCalendar(for: id)
        save()
    }

    // MARK: - 用例：彻底删除

    /// 从记录里抹掉。不可恢复，界面上必须先确认。
    func delete(id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        removeFromCalendar(reminders[index])
        reminders.remove(at: index)
        save()
    }

    // MARK: - 用例：稍后

    /// 「晚点再说」。
    /// - 定时类：真的把日历里的事件挪到新时间（这样手机日历也跟着改）。
    /// - 截止类 / 重复类：只在本 App 里再响一次，**不动日历**，否则就改了截止日本身。
    func snooze(id: UUID, until date: Date) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].snoozedUntil = date
        reminders[index].fireCount = 0
        reminders[index].lastFiredAt = nil

        if reminders[index].kind == .moment {
            reminders[index].dueAt = date
            syncCalendar(for: id)
        }
        save()
    }

    // MARK: - 用例：改时间

    func reschedule(id: UUID, to date: Date) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }

        switch reminders[index].kind {
        case .deadline:
            reminders[index].deadlineAt = date
            reminders[index].stageIndex = 0
        case .pool:
            reminders[index].kind = .moment
            reminders[index].dueAt = date
        default:
            reminders[index].dueAt = date
            reminders[index].fireCount = 0
        }

        reminders[index].snoozedUntil = nil
        reminders[index].lastFiredAt = nil
        syncCalendar(for: id)
        save()
    }

    // MARK: - 用例：响过之后推进状态

    func didFire(id: UUID, at fireDate: Date) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        reminders[index].lastFiredAt = now
        reminders[index].fireCount += 1
        reminders[index].snoozedUntil = nil

        switch reminders[index].kind {
        case .deadline:
            reminders[index].stageIndex += 1
        case .recurring:
            if let rule = reminders[index].recurrence {
                reminders[index].pendingOccurrence = reminders[index].dueAt
                let anchor = max(now, reminders[index].dueAt ?? now)
                reminders[index].dueAt = RecurrenceEngine.next(after: anchor, rule: rule)
                reminders[index].fireCount = 0
                reminders[index].lastFiredAt = nil
                syncCalendar(for: id)
            }
        case .pool:
            reminders[index].nudgedAt = now
        case .moment:
            break
        }

        // 开机补课：如果这一档已经晚了很久，把剩下的追提醒一次性作废，
        // 免得"关机三天后开机连炸三条"。
        let reference = reminders[index].kind == .deadline
            ? reminders[index].deadlineAt
            : reminders[index].dueAt
        if let reference, now.timeIntervalSince(reference) > 3600 {
            reminders[index].fireCount = 99
            reminders[index].stageIndex = 99
        }

        _ = fireDate
        save()
    }

    // MARK: - 用例：待办池抽签

    func pickPoolCandidate() -> Reminder? {
        let pool = poolList()
        guard !pool.isEmpty else { return nil }
        return pool.min { ($0.nudgedAt ?? .distantPast) < ($1.nudgedAt ?? .distantPast) }
    }

    func markPoolNudged(id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].nudgedAt = Date()
        save()
    }

    // MARK: - 日历同步

    /// 把本地状态推到日历。失败不阻塞本地使用，只记录。
    func syncCalendar(for id: UUID) {
        guard settings.calendarSyncEnabled, calendar.isAvailable else { return }
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        guard reminders[index].isActive, reminders[index].kind.writesToCalendar else {
            removeFromCalendar(reminders[index])
            return
        }
        do {
            let offsets = ScheduleRule.calendarAlarmOffsets(for: reminders[index], settings: settings)
            if let eventID = try calendar.apply(reminders[index], alarmOffsets: offsets) {
                reminders[index].calendarEventID = eventID
            }
        } catch {
            NSLog("[别忘] 写日历失败：\(error.localizedDescription)")
        }
    }

    /// 启动时补齐：之前没同步过的、或日历被手动清空的，都补回来
    func repairCalendarLinks() {
        guard settings.calendarSyncEnabled, calendar.isAvailable else { return }
        for item in active where item.kind.writesToCalendar {
            if let eventID = item.calendarEventID, calendar.exists(eventID) {
                continue
            }
            syncCalendar(for: item.id)
        }
        save()
    }

    private func removeFromCalendar(_ reminder: Reminder) {
        guard settings.calendarSyncEnabled else { return }
        calendar.remove(reminder)
    }
}
