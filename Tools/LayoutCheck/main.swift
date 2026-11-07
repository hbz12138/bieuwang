// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import AppKit

// 一个不上屏的自检工具：把面板搭起来、跑一遍布局，
// 检查有没有约束冲突或尺寸为 0 的控件。用来在没有截图权限时验证界面。

func walk(_ view: NSView, depth: Int = 0, path: String = "root") {
    let pad = String(repeating: "  ", count: depth)
    let frame = view.frame
    var flags: [String] = []
    if view.hasAmbiguousLayout { flags.append("AMBIGUOUS") }
    if frame.width <= 0 || frame.height <= 0 { flags.append("ZERO") }
    if view.isHidden { flags.append("hidden") }

    let name = String(describing: type(of: view))
    if !flags.isEmpty || view.isHidden == false {
        print("\(pad)- \(name) [\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))] \(flags.joined(separator: " "))")
    }
    for sub in view.subviews {
        walk(sub, depth: depth + 1, path: path + "/" + name)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bieuwang-layout-check")
try? FileManager.default.removeItem(at: temp)
try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

let environment = AppEnvironment(directory: temp)
let library = environment.library

// 放几种不同类型的数据，让每一行都真的被渲染
var moment = Reminder(title: "测试：下午三点开会", kind: .moment)
moment.dueAt = Date().addingTimeInterval(300)
library.upsert(moment)

var deadline = Reminder(title: "测试：周五前交材料", kind: .deadline)
deadline.deadlineAt = Date().addingTimeInterval(86400 * 3)
deadline.note = "提前三天开始提醒"
library.upsert(deadline)

let pool = Reminder(title: "测试：给妈妈回个电话", kind: .pool)
library.upsert(pool)

let controller = PopoverController(library: library)
let view = controller.view
view.frame = NSRect(x: 0, y: 0, width: 400, height: 560)
view.layoutSubtreeIfNeeded()

print("=== 布局树 ===")
walk(view)

print("\n=== 关键元素 ===")
print("行数：", view.subviews.count)
var ambiguous = 0
func countAmbiguous(_ v: NSView) {
    if v.hasAmbiguousLayout { ambiguous += 1 }
    v.subviews.forEach(countAmbiguous)
}
countAmbiguous(view)
print("模糊布局数量：", ambiguous)

print("\n=== 数据 ===")
print("今天：", library.todayList().count)
print("待办池：", library.poolList().count)
print("之后：", library.upcomingList().count)

// === 检查两个表单窗口 ===
func inspectWindow(_ label: String, _ window: NSWindow, targetWidth: CGFloat) {
    guard let content = window.contentView else { return }
    content.layoutSubtreeIfNeeded()
    let fitting = content.fittingSize
    var ambiguous = 0
    func scan(_ v: NSView) {
        if v.hasAmbiguousLayout { ambiguous += 1 }
        v.subviews.forEach(scan)
    }
    scan(content)
    print("\(label): 窗口 \(Int(window.frame.width))x\(Int(window.frame.height))，内容需要 \(Int(fitting.width))x\(Int(fitting.height))，模糊 \(ambiguous)")
}

let editor = EditorController(library: library, existing: nil, defaultKind: .moment) {}
inspectWindow("新建表单", editor.window, targetWidth: 460)

let repeating = EditorController(library: library, existing: nil, defaultKind: .recurring) {}
inspectWindow("重复表单", repeating.window, targetWidth: 460)

let settings = SettingsController(library: library) {}
inspectWindow("设置窗口", settings.window, targetWidth: 520)
