<div align="center">
  <img src="docs/images/icon.png" width="128" alt="别忘">
  <h1>别忘 (Bieuwang)</h1>
  <p><b>一个住在 macOS 菜单栏里的提醒工具</b><br>到点会响 · 响的时候能改时间 · 错过了会补课</p>
</div>

<p align="center">
  <a href="https://github.com/hbz12138/bieuwang/releases/latest/download/Bieuwang-0.1.0.dmg">
    <img src="https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-Bieuwang--0.1.0.dmg-24292F?logo=github&logoColor=white" alt="下载">
  </a>
  <img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue" alt="许可证">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B%20%C2%B7%20arm64-lightgrey" alt="平台">
  <img src="https://img.shields.io/badge/tests-29%20passing-brightgreen" alt="测试">
  <img src="https://img.shields.io/github/v/release/hbz12138/bieuwang?color=green" alt="版本">
</p>

<p align="center">
  <a href="#为什么又做一个提醒工具">为什么</a> •
  <a href="#功能">功能</a> •
  <a href="#安装">安装</a> •
  <a href="#使用">使用</a> •
  <a href="#从源码构建">构建</a> •
  <a href="#许可证">许可证</a>
</p>

---

## 为什么又做一个提醒工具

现成的工具通常断在一个地方：**提醒只在它被创建的那个界面里出现。**

于是出现三种典型失效——你换了窗口就看不见；它响的时候你正忙，只能关掉，然后就没有然后了；你关掉电脑几天，它既不响也不告诉你有多少事已经过期。**错过等于消失。**

别忘针对的就是这三处：

| 常见问题 | 这里的做法 |
|---|---|
| 提醒藏在某个会话或某个列表里 | 独立的菜单栏面板 + 系统通知，任何时候都在 |
| 响了没法立刻改时间 | 通知上直接「10 分钟后 / 1 小时后 / 今晚再说 / 完成了」 |
| 错过就没了 | 过期的一直标红留在「今天」；开机补响一次，不静默消失 |

---

## 功能

- **四种提醒，按"有没有截止时间"分流**
  - `定时` —— 几点做什么，到点响；没处理会在 15 分钟、1 小时后各追一次
  - `截止` —— 提前 3 天 / 1 天 / 2 小时 / 到点，逐级加强
  - `重复` —— 每天 / 工作日 / 每周 / 每月；这一期没做，不影响下一期
  - `待办池` —— 没定时间的杂事，每天空闲时**只抽一件**问你
- **写进系统日历** —— 单独一个叫「别忘」的日历，随 iCloud 同步到 iPhone / iPad；App 关着也由系统日历负责响
- **改时间会同步日历** —— 「定时」类推迟时，日历事件就地改时间，手机也跟着变
- **后悔药** —— 完成和放弃都进「记录」，点左边圆点一键恢复
- **可迁移** —— 全部数据是一个 `reminders.json`，拷走即走
- **本地优先** —— 不联网、无账号、不收集任何数据

---

## 安装

1. 从 [Releases](https://github.com/hbz12138/bieuwang/releases/latest) 下载 `Bieuwang-x.y.z.dmg`
2. 打开，把「别忘」拖进「应用程序」
3. 双击启动

### 第一次打开被系统拦下？

这是预期行为：本项目**没有做 Apple 公证**（需要付费开发者账号）。

macOS 26 之后，旧的「右键 → 打开」已经失效，正确做法是：

- 打开 **系统设置 → 隐私与安全性**，向下滚动，会看到关于「别忘」的提示，点 **仍要打开**；
- 或在终端执行：

  ```bash
  xattr -d com.apple.quarantine /Applications/别忘.app
  ```

### 首次启动会请求两项权限

| 权限 | 用途 |
|---|---|
| 日历 | 把提醒写进「别忘」日历，用于 iCloud 同步与后台提醒 |
| 通知 | 到点弹出提醒 |

拒绝也不影响本地记录，只是不会主动提醒你。

---

## 使用

打开菜单栏的 ✓ 图标，面板分为四栏：

| 分栏 | 内容 |
|---|---|
| **今天** | 今天到点的，以及**已经过期**的（标红） |
| **待办池** | 没有时间的事，等空闲时被抽问 |
| **以后** | 明天及以后 |
| **记录** | 已完成 / 已放弃，都可恢复 |

完整的使用方法、四类提醒怎么选、每天两分钟怎么维护，见 **[docs/USAGE.md](docs/USAGE.md)**。

---

## 数据与隐私

- 数据位置在你首次启动时选择的文件夹里，只有一个 `reminders.json`（人可读的 JSON）
- 程序不发起任何网络请求，没有账号体系，不上报任何内容
- 只写入自建的「别忘」日历，**不读取**你已有的日程
- 删除 App 不会删除数据；要彻底清理，删掉那个文件夹，并在日历 App 里删除「别忘」日历

---

## 系统要求

- macOS 13 或更新版本
- **仅 Apple Silicon（arm64）** —— Intel Mac 无法运行。交叉编译说明见 [`build.sh`](build.sh) 顶部注释

---

## 从源码构建

只需要 Apple 命令行工具，**不需要完整 Xcode**：

```bash
xcode-select --install   # 如果还没装
git clone https://github.com/hbz12138/bieuwang.git
cd bieuwang
make app                 # 编译出 build/别忘.app
make run                 # 编译并启动
make dmg                 # 打安装包
```

| 命令 | 作用 |
|---|---|
| `make app` | 编译 `.app` |
| `make run` | 编译并重启 |
| `make check` | 编译 / 签名 / 布局 / 功能测试 / 启动冒烟，五项全过才返回 0 |
| `make dmg` | 生成 `build/别忘.dmg` |
| `make fmt` | 用 `swift-format` 格式化源码 |

> 本机没有完整 Xcode，因此界面用 AppKit 手写而非 SwiftUI（SwiftUI 的宏需要 Xcode 才可用）。详见 [DEVELOPMENT.md](DEVELOPMENT.md)。

---

## 项目结构

```
Sources/
├── Domain/        数据模型与规则（不依赖 AppKit / EventKit，可脱离界面运行）
├── Persistence/   JSON 文档读写（原子写入，损坏时先备份）
├── Integrations/  日历 / 通知 / .ics 导出，各自实现一个协议，可整体替换
├── Application/   依赖组装与定时引擎
├── UI/            AppKit 手写界面（只负责渲染与转交动作）
└── App/           入口与菜单栏
```

分层原则：业务规则不碰界面，外部系统全部走协议。想换成 Google 日历，只需在 `Integrations/` 新增一个实现，`Domain` 与 `UI` 无需改动。

---

## 测试

没有完整 Xcode，因此不使用 XCTest，改用可执行的自检程序：

```bash
make check
```

```
▸ 1/5 编译 App            通过
▸ 2/5 代码签名与包结构      通过
▸ 3/5 界面布局            通过（0 个模糊约束）
▸ 4/5 功能测试            通过（通过 29，失败 0）
▸ 5/5 启动冒烟            启动正常
```

29 项功能测试只走**用户能做的动作**（点按钮、改输入框、切分栏），只断言**用户能看见的结果**（列表里有没有、状态对不对）。

---

## 贡献

Issue 和 Pull Request 都欢迎。改动前请先跑一次 `make check`，并保持「业务规则不碰界面」这条分层约定。

由于采用 GPL-3.0，你提交的修改会以同一许可证发布。

---

## 许可证

**别忘 (Bieuwang)**  
Copyright (C) 2026 hbz12138

本程序是自由软件：你可以依据自由软件基金会发布的 **GNU 通用公共许可证**（第 3 版，或你选择的任何更新版本）的条款重新发布和/或修改它。

本程序的发布是希望它有用，但**不提供任何担保**，甚至不提供适销性或特定用途适用性的默示担保。详见 GNU 通用公共许可证。

你应该已经随程序收到一份 GNU 通用公共许可证的副本。如果没有，请见 <https://www.gnu.org/licenses/>。

| | |
|---|---|
| 许可证全文 | [LICENSE](LICENSE) |
| SPDX 标识 | `GPL-3.0-or-later` |
| 全文地址 | <https://www.gnu.org/licenses/gpl-3.0.html> |

---

<p align="center">
  <sub>本项目与 Apple Inc. 无关。macOS、iCloud、Calendar 是 Apple Inc. 的商标。</sub>
</p>
