// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import Foundation

// MARK: - 定时器
//
// 只做一件事：每隔一会儿看看有没有到点的，有就交给 library + notifier。
// 不含任何业务规则——规则在 ScheduleRule，状态变更在 ReminderLibrary。

final class SchedulingEngine {

    private let library: ReminderLibrary
    private let notifier: ReminderNotifying
    private var timer: Timer?
    private var lastPoolSlotKey: String = ""
    private let tickInterval: TimeInterval = 15

    init(library: ReminderLibrary, notifier: ReminderNotifying) {
        self.library = library
        self.notifier = notifier
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: 一轮检查

    private func tick() {
        let now = Date()
        let quiet = isQuietHours(now)

        for reminder in library.active {
            guard let fireAt = ScheduleRule.nextFire(for: reminder, after: now.addingTimeInterval(-1),
                                                    settings: library.settings) else { continue }
            guard fireAt <= now else { continue }

            // 免打扰时段：只有"刚刚到点（30 分钟内）且是主提醒"才允许响。
            // 深夜不追债，也不拿一堆早就过期的提醒轰炸你。
            if quiet {
                let late = now.timeIntervalSince(fireAt)
                let primary = ScheduleRule.isPrimaryOccurrence(reminder, settings: library.settings)
                guard late <= 1800, primary else { continue }
            }

            // 先落状态，再发通知：避免同一分钟里重复响
            library.didFire(id: reminder.id, at: fireAt)
            notifier.post(reminder, at: fireAt)
        }

        // 待办池属于"可打扰"，免打扰时段一律不抽
        if !quiet {
            checkPool(now: now)
        }
    }

    // MARK: 待办池：一天抽几件

    private func checkPool(now: Date) {
        guard let candidate = library.pickPoolCandidate() else { return }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let stamp = String(format: "%02d:%02d", hour, minute)

        let dayKey = "\(calendar.startOfDay(for: now).timeIntervalSince1970)-\(stamp)"
        guard library.settings.idleNudgeTimes.contains(stamp),
              lastPoolSlotKey != dayKey else { return }
        lastPoolSlotKey = dayKey

        library.markPoolNudged(id: candidate.id)
        notifier.postPoolPick(candidate)
    }

    // MARK: 免打扰

    private func isQuietHours(_ now: Date) -> Bool {
        guard let (fromHour, fromMinute) = ClockText.parse(library.settings.quietFrom),
              let (toHour, toMinute) = ClockText.parse(library.settings.quietTo) else { return false }

        let calendar = Calendar.current
        let current = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let from = fromHour * 60 + fromMinute
        let to = toHour * 60 + toMinute

        if from == to { return false }
        if from < to { return current >= from && current < to }
        return current >= from || current < to
    }
}
