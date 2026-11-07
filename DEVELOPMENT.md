# 开发环境说明

> 这台机器**没有装完整的 Xcode**，只有 Apple 命令行工具。这不是问题，但有几条硬约束必须先知道，否则会重复踩同一个坑。

## 一、环境现状

| 项目 | 情况 |
|---|---|
| macOS | 27.2（arm64） |
| 开发目录 | `/Library/Developer/CommandLineTools` |
| Swift | 6.4.2 |
| macOS SDK | 27.2 |
| Homebrew | 有 |
| **Xcode** | **没有**（完整安装需要 40 GB 以上磁盘，本机放不下） |

## 二、能做 / 不能做

| 能 | 不能 |
|---|---|
| 编译任何原生 AppKit 程序 | ❌ 用 SwiftUI 的 `@State` / `@Bindable` 等**宏** |
| 打包 `.app`、`.dmg`、自签名 | ❌ iOS 开发、模拟器（`simctl` 不存在） |
| 交叉编译 x86_64（未真机验证） | ❌ 公证分发（需要开发者证书 + `notarytool`） |
| `swift-format` 格式化 | ❌ `xcodebuild`、Instruments、XCTest |
| `sourcekit-lsp`（编辑器补全） | ❌ Playgrounds |

## 三、六条坑（都是这次实际踩到的）

### 1. SwiftUI 编译不了
```
error: external macro implementation type 'SwiftUIMacros.StateMacro'
could not be found for macro 'State()'
```
原因：`libSwiftUIMacros.dylib` 只随 Xcode 分发，命令行工具里没有。

**对策**：界面一律用 AppKit 手写。本项目的 `Sources/UI/` 就是这么写的。
如果你以后确实需要 SwiftUI，只有装 Xcode 一条路。

### 2. codesign 报 "resource fork, Finder information, or similar detritus not allowed"
新建的文件会带 `com.apple.provenance` / `com.apple.FinderInfo` 扩展属性。

**对策**：签名前 `xattr -cr "$APP"`；`build.sh` 里已经做了，且失败会自动再清一次重试。

### 3. 顶层代码只能写在 `main.swift` 里
其他文件写顶层语句会报 `expressions are not allowed at the top level`。

**对策**：自检程序都放成 `Tools/xxx/main.swift`。

### 4. 没有 XCTest，不能跑单元测试
**对策**：用可以执行的自检程序代替，`make check` 会跑两套：
- `Tools/LayoutCheck` —— 把界面搭起来跑一遍布局，断言 **0 个模糊约束**、控件不为 0 尺寸；
- `Tools/Tests` —— **21 项功能测试**，分两组：
  - 数据与规则：新建/完成/稍后/改期/重复推进/补课/持久化/坏文件恢复/导出
  - 界面：点＋能不能加上、**加完当前分栏看不看得见**、空输入、空格裁剪、
    待办池归位、分栏切换、表单保存/取消、行的完成按钮

**这些测试只走"用户能做的动作"**（点按钮、改输入框、切分栏），只断言"用户能看见的结果"（列表里有没有）。
不测内部私有函数——因为用户遇到的 bug 从来不在那些地方。

> 写这类测试有个坑：`NSControl.target` 是**弱引用**。如果测试里把控制器丢掉，
> 按钮的 target 会变成 nil，于是误报"按钮没接线"。正确写法是用
> `withExtendedLifetime(controller) { ... }` 把它活到断言结束。

### 5. 自签名应用，TCC 权限会不会每次重编译都要重新授权？
实测：**不会**。重新编译后旧的日历权限仍然有效，新加的提醒照样拿到了 `calendarEventID`。
但如果哪天你发现又弹授权窗了，去「系统设置 → 隐私与安全性 → 日历」里看一眼即可。

### 6. 中文路径要加引号
工程路径里有「别忘.app」。shell 里一律写 `"$APP"`，别偷懒。

## 四、日常流程

```bash
make app      # 编译
make run      # 编译并重启（改完代码用这个，一步到位）
make check    # 交付前必跑
make dmg      # 打安装包
```

`make check` 的顺序是：编译 → 验签名 → 布局自检 → 按钮接线自检。**任何一项红，都不要说"做完了"。**

## 五、代码放哪儿

```
Sources/
├── Domain/        纯规则。不 import AppKit、不 import EventKit，可以脱离界面单独跑
├── Persistence/   一个 JSON 文件，原子写入，坏了先备份
├── Integrations/  日历 / 通知 / .ics。每个都实现一个协议，可整体替换
├── Application/   组装依赖（唯一知道谁依赖谁的地方）+ 定时器
├── UI/            AppKit 手写界面，只画画
└── App/           入口 + 菜单栏
```

**加功能的判断法**：

| 你想加的东西 | 改哪 |
|---|---|
| 一条新的提醒规则（比如"每隔 N 天"） | `Domain/ScheduleRule.swift` + `Recurrence` |
| 换一种日历（Google / Outlook） | `Integrations/` 新写一个类，`AppEnvironment` 换一行 |
| 换一种提醒方式（声音、弹窗） | `Integrations/Notifier` 的协议实现 |
| 界面改动 | 只动 `UI/`，不碰规则 |

**不要**在 `UI/` 里写业务规则，也不要在 `Domain/` 里 import AppKit —— 这条线一破，测试和替换都做不了。

## 六、如果将来想装 Xcode

先把磁盘腾到 **60 GB 以上**（Xcode 本体 + 模拟器 + 缓存）。装完后执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

然后 `Sources/UI` 才有资格改用 SwiftUI。**在此之前，AppKit 就是这里的正确选择，不是妥协。**
