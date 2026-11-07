// SPDX-License-Identifier: GPL-3.0-or-later
// 别忘 (Bieuwang) — 一个住在菜单栏里的提醒工具
// Copyright (C) 2026 hbz12138
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新发布和/或修改它。
// 本程序希望有用，但不提供任何担保，甚至不提供适销性或特定用途适用性的默示担保。
// 详见 LICENSE 文件或 <https://www.gnu.org/licenses/>。

import AppKit

// 生成 App 图标：蓝色圆角方块 + 白色对勾。纯 CoreGraphics，不依赖外部工具。

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
let rect = CGRect(x: 0, y: 0, width: size, height: size)

// 圆角底
let radius = size * 0.22
let path = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: radius, yRadius: radius)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.24, green: 0.47, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.09, green: 0.24, blue: 0.78, alpha: 1)
])!
gradient.draw(in: path, angle: -90)

// 对勾
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineWidth(size * 0.085)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: size * 0.27, y: size * 0.52))
ctx.addLine(to: CGPoint(x: size * 0.44, y: size * 0.33))
ctx.addLine(to: CGPoint(x: size * 0.75, y: size * 0.68))
ctx.strokePath()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try? png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
