// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import Foundation

// MARK: - 一整份数据就是一个 JSON 文件
//
// 拷走它 = 拷走全部。换电脑、放云盘、放 U 盘都只是"换一个文件夹"。

final class JSONDocumentFile: DocumentPersisting {

    private(set) var fileURL: URL

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("reminders.json")
    }

    func load() throws -> ReminderDocument? {
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard fm.fileExists(atPath: fileURL.path) else {
            // 第一次运行就把文件落下来：用户能立刻看到"我的数据在哪"
            let fresh = ReminderDocument.empty(at: fileURL.deletingLastPathComponent().path)
            try save(fresh)
            return fresh
        }

        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder.bieuwang.decode(ReminderDocument.self, from: data)
        } catch {
            // 文件坏了：先备份，再当作空文档，绝不静默丢数据
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("reminders.broken-\(stamp).json")
            try? data.write(to: backup)
            NSLog("[别忘] JSON 无法解析，已备份到 \(backup.path)")
            return ReminderDocument.empty(at: fileURL.deletingLastPathComponent().path)
        }
    }

    func save(_ document: ReminderDocument) throws {
        let data = try JSONEncoder.bieuwang.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    func relocate(to directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("reminders.json")
    }
}
