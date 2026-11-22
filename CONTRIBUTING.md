# 参与贡献

感谢你愿意花时间。这份文档说明**改动是怎么进入项目的**——不是规定，是流程，照着做能省掉来回沟通。

---

## 一、三种参与方式

| 你想做的 | 怎么做 |
|---|---|
| 报问题 | 开 [Issue](https://github.com/hbz12138/bieuwang/issues)，说清楚「期望什么 / 实际什么 / 怎么复现」 |
| 改代码 | 走下面的 **PR 流程**。没有写权限的话先 Fork |
| 只是自己用 | 直接 Fork 或下载，GPL 允许你随便改，不必告诉我们 |

---

## 二、为什么不让直接改 `main`

`main` 分支对应「随时可以发版」的状态。

**一次改动如果直接进 `main`，就没有任何一个时刻能让别人完整看一遍 diff。** PR 的全部价值就在这里：它把「改」和「合」拆成两步，中间留出看的机会。

---

## 三、提交一个 PR 的完整流程

### 1. 从最新 `main` 开分支

```bash
git switch main
git pull
git switch -c fix/tab-jumps-after-add
```

分支名建议带类型前缀：

| 前缀 | 用于 |
|---|---|
| `feat/` | 新功能 |
| `fix/` | 修 bug |
| `docs/` | 只改文档 |
| `refactor/` | 不改行为的重构 |
| `chore/` | 构建、依赖、格式 |

### 2. 改代码，然后自己先验一遍

```bash
make check
```

五项全过才提 PR：编译 / 签名 / 布局 / 29 项功能测试 / 启动冒烟。

**这一条是硬要求**，因为 CI 还没配，你就是 CI。

### 3. 提交

```bash
git add -A
git commit -m "修复：添加提醒后不跳转到对应分栏"
```

提交信息用「类型：一句话」，说**做了什么**，不说「修改了一些代码」。

### 4. 推送并开 PR

```bash
git push -u origin fix/tab-jumps-after-add
gh pr create --base main --title "修复：添加提醒后不跳转到对应分栏" --body "..."
```

不想用命令行，推送后 GitHub 会在仓库页顶部显示「Compare & pull request」按钮，点它也一样。

### 5. 等审查 / 自己看一遍 diff

在 PR 的 **Files changed** 里逐行看。行号左边点一下就能留评论，攒几条后点 **Start a review** 一次性提交。

### 6. 合并

推荐 **Squash and merge**：把一个分支的零碎提交压成一条，`main` 的历史保持一行一件事。

合并后删掉分支（GitHub 界面有按钮，或 `git push origin --delete 分支名`）。

---

## 四、想让别人来审，怎么弄

这是新手最容易卡住的地方：**仓库默认只有你一个人，没有「别人」可选。**

| 目标 | 做法 |
|---|---|
| 让某个人能审 | 仓库 **Settings → Collaborators → Add people**，对方接受邀请后，PR 右侧 **Reviewers** 里就能选到他 |
| 希望 PR 自动指派给某人 | 在 `.github/CODEOWNERS` 里写规则，本仓库已配置 `* @hbz12138` |
| 强制「必须有审查才能合并」 | **Settings → Branches → Add branch protection rule**，勾选 *Require a pull request before merging* 和 *Require approvals* |
| 只是想让别人看看 | 把 PR 链接发给他，他**不需要权限也能评论**（公开仓库任何人都能评论） |

> ⚠️ 单人维护时**不要**开启「Require approvals」：GitHub 不允许你给自己的 PR 记一次有效批准，你会把自己锁在门外。

---

## 五、审查意见怎么处理

| 对方的操作 | 意思是 | 你该做什么 |
|---|---|---|
| **Comment** | 只是提意见，不拦你 | 看情况改，回一句 |
| **Request changes** | 有问题，**不能合** | 改完推送同一分支，PR 会自动更新，然后点 **Re-request review** |
| **Approve** | 可以合了 | 合并 |

被指出的问题改完后，在对应评论下点 **Resolve conversation**，让审查的人一眼看出哪些已经处理了。

**不要 force push 到正在被审的分支**——那会让行内评论失去锚点。用普通的追加提交，合并时再 squash。

---

## 六、这个项目的一条硬约定

改动要守住分层：

```
Domain（规则，不 import AppKit / EventKit）
   ↑
Application（组装）
   ↑
UI（只渲染，不含业务规则）
```

- 业务规则写进 `UI/` → 会被要求改
- 在 `Domain/` 里 `import AppKit` → 会被要求改
- 新增一个外部系统（比如 Google 日历）→ 在 `Integrations/` 加一个协议实现，不改 `Domain`

---

## 七、许可证

本项目采用 **GPL-3.0-or-later**。你提交的 PR 会被视为同意以同一许可证发布。

这意味着：别人可以继续改、继续发，但不能把它变成闭源私有版本。
