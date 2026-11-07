// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import AppKit

// 标准化功能测试。
// 原则：只通过"用户能做的动作"去驱动（点按钮、改输入框、切分栏），
// 断言"用户能看见的结果"（列表里有没有、条数对不对），而不是只测内部函数。

var passed = 0
var failed = 0
var failures: [String] = []

func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        passed += 1
        print("  ✅ \(name)")
    } catch {
        failed += 1
        let message = "\(name) —— \(error.localizedDescription)"
        failures.append(message)
        print("  ❌ \(message)")
    }
}

struct TestFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(message: message) }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String) throws {
    if a != b { throw TestFailure(message: "\(message)（实际 \(a)，期望 \(b)）") }
}

// MARK: - 界面探针

func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

func editableField(_ v: NSView) -> NSTextField? {
    allViews(v).compactMap { $0 as? NSTextField }.first { $0.isEditable }
}

func button(_ v: NSView, action: String) -> NSButton? {
    allViews(v).compactMap { $0 as? NSButton }
        .first { $0.action.map(NSStringFromSelector) == action }
}

func segmentedControl(_ v: NSView) -> NSSegmentedControl? {
    allViews(v).compactMap { $0 as? NSSegmentedControl }.first
}

func rowCount(_ v: NSView) -> Int {
    allViews(v).filter { $0 is ReminderRowView }.count
}

func selectTab(_ control: NSSegmentedControl, _ index: Int) {
    control.selectedSegment = index
    if let target = control.target, let action = control.action {
        _ = target.perform(action, with: control)
    }
}

// MARK: - 环境

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func freshLibrary() -> (ReminderLibrary, URL) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("bw-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let document = JSONDocumentFile(directory: dir)
    let library = ReminderLibrary(document: document,
                                 calendar: EventKitCalendarSync(calendarName: "测试"),
                                 notifier: SystemNotifier())
    return (library, dir)
}

func freshPopover() -> (PopoverController, ReminderLibrary, NSView) {
    let (library, _) = freshLibrary()
    let controller = PopoverController(library: library)
    let view = controller.view
    view.frame = NSRect(x: 0, y: 0, width: 400, height: 560)
    view.layoutSubtreeIfNeeded()
    return (controller, library, view)
}

print("\n=== 一、数据与规则 ===")

test("新建定时提醒：时间、状态正确") {
    let (library, _) = freshLibrary()
    var item = Reminder(title: "开会", kind: .moment)
    let due = Date().addingTimeInterval(3600)
    item.dueAt = due
    library.upsert(item)

    let saved = library.active.first
    try expectEqual(library.active.count, 1, "条数")
    try expect(saved?.kind == .moment, "类型应为定时")
    try expect(abs((saved?.dueAt ?? .distantPast).timeIntervalSince(due)) < 1, "时间应保持")
    try expect(saved?.status == .active, "状态应为进行中")
}

test("新建待办：不占用时间") {
    let (library, _) = freshLibrary()
    library.upsert(Reminder(title: "回电话", kind: .pool))
    let saved = library.active.first
    try expect(saved?.dueAt == nil, "待办不该有 dueAt")
    try expectEqual(library.poolList().count, 1, "应在待办池里")
}

test("新建截止：算出提前提醒档位") {
    let (library, _) = freshLibrary()
    var item = Reminder(title: "交材料", kind: .deadline)
    let deadline = Date().addingTimeInterval(86400 * 3)
    item.deadlineAt = deadline
    library.upsert(item)

    let settings = library.settings
    let first = ScheduleRule.nextFire(for: library.active[0],
                                      after: Date().addingTimeInterval(-10),
                                      settings: settings)
    try expect(first != nil, "应能算出下一次提醒")
    let delta = (first ?? .distantPast).timeIntervalSince(deadline)
    try expect(abs(delta + 3 * 86400) < 60, "第一次应是提前 3 天（实际差 \(Int(delta)) 秒）")
}

test("重复提醒：完成后跳到下一期，并且仍然有效") {
    let (library, _) = freshLibrary()
    var item = Reminder(title: "浇花", kind: .recurring)
    let rule = Recurrence(freq: .daily, hour: 9, minute: 0, weekday: nil, monthDay: nil)
    item.recurrence = rule
    item.dueAt = Date().addingTimeInterval(-60)   // 已经到点
    library.upsert(item)

    let id = library.active[0].id
    library.didFire(id: id, at: Date())
    library.complete(id: id)

    let saved = library.active.first
    try expect(saved != nil, "完成后不应消失")
    try expect(saved?.status == .active, "重复任务完成后仍是进行中")
    try expect((saved?.dueAt ?? .distantPast) > Date(), "下一期应在将来")
}

test("完成定时提醒：移出进行中，进入完成列表") {
    let (library, _) = freshLibrary()
    library.upsert(Reminder(title: "吃药", kind: .moment, dueAt: Date()))
    let id = library.active[0].id
    library.complete(id: id)

    try expectEqual(library.active.count, 0, "进行中应为 0")
    try expectEqual(library.doneList().count, 1, "完成列表应有 1 条")
    try expect(library.doneList()[0].completedAt != nil, "应记录完成时间")
}

test("稍后 10 分钟：定时类会同时改时间") {
    let (library, _) = freshLibrary()
    var item = Reminder(title: "开会", kind: .moment)
    item.dueAt = Date()
    library.upsert(item)

    let id = library.active[0].id
    let target = Date().addingTimeInterval(600)
    library.snooze(id: id, until: target)

    let saved = library.active[0]
    try expect(saved.snoozedUntil != nil, "应有稍后时间")
    try expect(abs((saved.dueAt ?? .distantPast).timeIntervalSince(target)) < 1,
               "定时类的 dueAt 应跟着改")
}

test("稍后 10 分钟：截止类不动截止日") {
    let (library, _) = freshLibrary()
    var item = Reminder(title: "交材料", kind: .deadline)
    let deadline = Date().addingTimeInterval(86400)
    item.deadlineAt = deadline
    library.upsert(item)

    let id = library.active[0].id
    library.snooze(id: id, until: Date().addingTimeInterval(600))

    let saved = library.active[0]
    try expect(abs((saved.deadlineAt ?? .distantPast).timeIntervalSince(deadline)) < 1,
               "截止日不该被挪动")
}

test("错过的提醒：仍会返回一个过去的触发时刻（补课）") {
    let (library, _) = freshLibrary()
    var item = Reminder(title: "忘了的事", kind: .moment)
    item.dueAt = Date().addingTimeInterval(-3600)
    library.upsert(item)

    let fire = ScheduleRule.nextFire(for: library.active[0], after: Date(), settings: library.settings)
    try expect(fire != nil, "过期的提醒不应变成 nil，否则永远不会补响")
    try expect((fire ?? Date()) < Date(), "应返回过去时刻，由引擎立刻补响")
}

test("提醒不重复响：响过档位后就不再返回") {
    let (library, _) = freshLibrary()
    var item = Reminder(title: "一次性", kind: .moment)
    item.dueAt = Date().addingTimeInterval(-10)
    library.upsert(item)

    let id = library.active[0].id
    for _ in 0..<3 { library.didFire(id: id, at: Date()) }
    let fire = ScheduleRule.nextFire(for: library.active[0],
                                     after: Date(), settings: library.settings)
    try expect(fire == nil, "所有档位响完后不应再返回")
}

test("数据持久化：存盘后重新读取一致") {
    let (library, dir) = freshLibrary()
    library.upsert(Reminder(title: "存盘测试", kind: .pool))
    library.saveNow()

    let reopened = ReminderLibrary(document: JSONDocumentFile(directory: dir),
                                   calendar: EventKitCalendarSync(calendarName: "测试"),
                                   notifier: SystemNotifier())
    try expectEqual(reopened.active.count, 1, "重开后条数")
    try expectEqual(reopened.active[0].title, "存盘测试", "标题")
}

test("数据文件损坏：备份后重置，不崩") {
    let (_, dir) = freshLibrary()
    let file = dir.appendingPathComponent("reminders.json")
    try "{ 这不是合法 json".write(to: file, atomically: true, encoding: .utf8)

    let library = ReminderLibrary(document: JSONDocumentFile(directory: dir),
                                  calendar: EventKitCalendarSync(calendarName: "测试"),
                                  notifier: SystemNotifier())
    try expectEqual(library.active.count, 0, "坏文件应重置为空")
    let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .filter { $0.contains("broken") }
    try expect(!backups.isEmpty, "应留下备份文件")
}

test("导出 .ics：包含事件与提醒") {
    let (library, _) = freshLibrary()
    var item = Reminder(title: "导出测试", kind: .moment)
    item.dueAt = Date().addingTimeInterval(3600)
    library.upsert(item)

    let ics = ICSExporter.export(library.active)
    try expect(ics.contains("BEGIN:VEVENT"), "应包含事件")
    try expect(ics.contains("导出测试"), "应包含标题")
    try expect(ics.contains("BEGIN:VALARM"), "应包含提醒")
}

print("\n=== 二、界面：加完之后你看得见吗 ===")

// 注意：NSControl.target 是弱引用。测试里必须把控制器活到断言结束，
// 否则按钮的 target 变 nil，会误判成"按钮没接线"。

test("快速添加：点＋后数据里有一条") {
    let (vc, library, view) = freshPopover()
    try withExtendedLifetime(vc) {
        guard let field = editableField(view), let plus = button(view, action: "commitDraft") else {
            throw TestFailure(message: "找不到输入框或＋按钮")
        }
        field.stringValue = "买东西"
        plus.performClick(nil)
        try expectEqual(library.active.count, 1, "数据里应有一条")
    }
}

test("快速添加：点＋后当前分栏看得见它（这才是「没反应」的真凶）") {
    let (vc, library, view) = freshPopover()
    try withExtendedLifetime(vc) {
        guard let field = editableField(view), let plus = button(view, action: "commitDraft") else {
            throw TestFailure(message: "找不到输入框或＋按钮")
        }
        field.stringValue = "买东西"
        plus.performClick(nil)

        try expectEqual(library.active.count, 1, "数据里应有一条")
        try expect(rowCount(view) > 0,
                   "加完了列表里却看不见（它被放进了别的分栏，用户以为没加上）")
    }
}

test("快速添加：空输入不静默，也不加脏数据") {
    let (vc, library, view) = freshPopover()
    try withExtendedLifetime(vc) {
        guard let plus = button(view, action: "commitDraft") else {
            throw TestFailure(message: "找不到＋按钮")
        }
        plus.performClick(nil)
        try expectEqual(library.active.count, 0, "空输入不该产生数据")
    }
}

test("快速添加：首尾空格会被清掉") {
    let (vc, library, view) = freshPopover()
    try withExtendedLifetime(vc) {
        guard let field = editableField(view), let plus = button(view, action: "commitDraft") else {
            throw TestFailure(message: "找不到输入框或＋按钮")
        }
        field.stringValue = "   带空格的事情   "
        plus.performClick(nil)
        try expectEqual(library.active.first?.title, "带空格的事情", "标题应被裁剪")
    }
}

test("待办池：加了之后在待办池分栏里看得见") {
    let (vc, library, view) = freshPopover()
    try withExtendedLifetime(vc) {
        guard let popup = allViews(view).compactMap({ $0 as? NSPopUpButton }).first,
              let field = editableField(view),
              let plus = button(view, action: "commitDraft") else {
            throw TestFailure(message: "找不到类型选择或输入框")
        }
        popup.selectItem(withTitle: ReminderKind.pool.label)
        field.stringValue = "预约体检"
        plus.performClick(nil)

        try expectEqual(library.poolList().count, 1, "应在待办池里")
        try expect(rowCount(view) > 0, "当前分栏应能看见它")
    }
}

test("切换分栏：完成分栏里不出现未完成的事") {
    let (vc, library, view) = freshPopover()
    try withExtendedLifetime(vc) {
        var today = Reminder(title: "今天的事", kind: .moment)
        today.dueAt = Date().addingTimeInterval(60)
        library.upsert(today)

        guard let segmented = segmentedControl(view) else {
            throw TestFailure(message: "找不到分栏控件")
        }

        selectTab(segmented, 0)
        let todayRows = rowCount(view)
        selectTab(segmented, 3)
        let doneRows = rowCount(view)

        try expect(todayRows >= 1, "今天分栏应看到今天的事")
        try expectEqual(doneRows, 0, "完成分栏不该出现未完成的事")
    }
}

test("详细表单：保存后数据真的变了") {
    let (vc, library, _) = freshPopover()
    try withExtendedLifetime(vc) {
        _ = vc.perform(Selector(("openNewEditor")))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        guard let window = NSApp.windows.first(where: { $0.title == "新建提醒" }),
              let content = window.contentView,
              let save = button(content, action: "save") else {
            throw TestFailure(message: "表单没弹出来或找不到保存按钮")
        }
        if let field = editableField(content) { field.stringValue = "表单里加的" }
        save.performClick(nil)

        try expectEqual(library.active.count, 1, "表单保存应写入数据")
        try expectEqual(library.active.first?.title, "表单里加的", "标题")
    }
}

test("详细表单：取消不写入") {
    let (vc, library, _) = freshPopover()
    try withExtendedLifetime(vc) {
        _ = vc.perform(Selector(("openNewEditor")))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        guard let window = NSApp.windows.first(where: { $0.title == "新建提醒" }),
              let content = window.contentView,
              let cancel = button(content, action: "cancel") else {
            throw TestFailure(message: "找不到取消按钮")
        }
        if let field = editableField(content) { field.stringValue = "不该被保存" }
        cancel.performClick(nil)

        try expectEqual(library.active.count, 0, "取消后不该有数据")
    }
}

test("行的完成按钮：点了就完成") {
    let (vc, library, view) = freshPopover()
    try withExtendedLifetime(vc) {
        library.upsert(Reminder(title: "点我完成", kind: .moment, dueAt: Date()))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        guard let row = allViews(view).compactMap({ $0 as? ReminderRowView }).first,
              let complete = row.subviews.compactMap({ $0 as? NSButton }).first else {
            throw TestFailure(message: "找不到行或完成按钮")
        }
        complete.performClick(nil)
        try expectEqual(library.active.count, 0, "点完应移出进行中")
        try expectEqual(library.doneList().count, 1, "应进入完成列表")
    }
}

print("\n=== 三、误操作与恢复 ===")

test("完成之后可以一键恢复") {
    let (library, _) = freshLibrary()
    library.upsert(Reminder(title: "手滑点错了", kind: .moment, dueAt: Date()))
    let id = library.active[0].id

    library.complete(id: id)
    try expectEqual(library.active.count, 0, "先要真的完成掉")

    library.restore(id: id)
    try expectEqual(library.active.count, 1, "恢复后应回到进行中")
    try expect(library.active[0].completedAt == nil, "恢复后不该还留着完成时间")
}

test("恢复过期很久的事：时间会被顺延到将来，不会立刻标红") {
    let (library, _) = freshLibrary()
    var item = Reminder(title: "上周的事", kind: .moment)
    item.dueAt = Date().addingTimeInterval(-86400 * 7)
    library.upsert(item)
    let id = library.active[0].id

    library.complete(id: id)
    library.restore(id: id)

    let restored = library.active[0]
    try expect((restored.dueAt ?? .distantPast) > Date(), "应顺延到将来")
    try expectEqual(library.overdueCount, 0, "不应立刻变成过期")
}

test("已完成的事再点「不用了」，不会抹掉完成状态") {
    let (library, _) = freshLibrary()
    library.upsert(Reminder(title: "做完又被点", kind: .moment, dueAt: Date()))
    let id = library.active[0].id

    library.complete(id: id)
    library.drop(id: id)   // 旧逻辑会把完成改成放弃，划线就消失了

    let saved = library.reminder(id: id)
    try expect(saved?.status == .done, "状态应仍是已完成（实际 \(saved?.status.rawValue ?? "nil")）")
    try expect(saved?.completedAt != nil, "完成时间不该被清掉")
}

test("彻底删除：记录真的消失") {
    let (library, _) = freshLibrary()
    library.upsert(Reminder(title: "要删掉的", kind: .pool))
    let id = library.active[0].id

    library.delete(id: id)
    try expectEqual(library.active.count, 0, "进行中应为 0")
    try expect(library.doneList().isEmpty, "记录列表也应为空")
    try expect(library.reminder(id: id) == nil, "按 id 也查不到了")
}

test("完成页里那个圆点，点下去是「恢复」而不是再完成一次") {
    let (vc, library, view) = freshPopover()
    try withExtendedLifetime(vc) {
        library.upsert(Reminder(title: "点圆点试试", kind: .moment, dueAt: Date()))
        let id = library.active[0].id
        library.complete(id: id)

        guard let segmented = segmentedControl(view) else {
            throw TestFailure(message: "找不到分栏控件")
        }
        selectTab(segmented, 3)          // 切到「完成」
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        guard let row = allViews(view).compactMap({ $0 as? ReminderRowView }).first,
              let leading = row.subviews.compactMap({ $0 as? NSButton }).first else {
            throw TestFailure(message: "完成页里找不到行或圆点按钮")
        }

        leading.performClick(nil)
        try expectEqual(library.active.count, 1, "点圆点应把它恢复成进行中")
    }
}

print("\n=== 四、四个分栏的归类规则 ===")

test("归类：今天 / 以后 / 待办池 / 记录 各归各位") {
    let (library, _) = freshLibrary()
    let calendar = Calendar.current
    let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    let overdue = calendar.date(byAdding: .hour, value: -5, to: noon)!

    var past = Reminder(title: "过期的", kind: .moment); past.dueAt = overdue
    var todayNoon = Reminder(title: "今天中午的", kind: .moment); todayNoon.dueAt = noon
    var far = Reminder(title: "五天后的", kind: .moment)
    far.dueAt = calendar.date(byAdding: .day, value: 5, to: noon)!
    let poolItem = Reminder(title: "池子里的", kind: .pool)

    library.upsert(past)
    library.upsert(todayNoon)
    library.upsert(far)
    library.upsert(poolItem)

    try expect(library.todayList().contains { $0.title == "过期的" }, "过期的应出现在「今天」（红色）")
    try expect(library.todayList().contains { $0.title == "今天中午的" }, "今天的应出现在「今天」")
    try expect(!library.todayList().contains { $0.title == "五天后的" }, "五天后的不该出现在「今天」")
    try expect(library.upcomingList().contains { $0.title == "五天后的" }, "五天后的应在「以后」")
    try expectEqual(library.poolList().count, 1, "「待办池」只有池子里的")
    try expect(library.todayList().allSatisfy { $0.kind != .pool }, "池子不该混进「今天」")
}

test("归类：结束后只会出现在「记录」，不再占着前三个栏") {
    let (library, _) = freshLibrary()
    var item = Reminder(title: "做完的事", kind: .moment)
    item.dueAt = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    library.upsert(item)

    let id = library.active[0].id
    library.complete(id: id)

    try expect(library.todayList().isEmpty, "完成后不该留在「今天」")
    try expect(library.upcomingList().isEmpty, "完成后不该留在「以后」")
    try expect(!library.doneList().isEmpty, "应进入「记录」")
}

test("分栏名称就是用户看到的四个词") {
    let titles = MainTab.allCases.map { $0.title }
    try expectEqual(titles, ["今天", "待办池", "以后", "记录"], "分栏顺序与名称")
}

print("\n=== 结果 ===")
print("通过 \(passed)，失败 \(failed)")
if failed > 0 {
    for f in failures { print("  · \(f)") }
    exit(1)
}
