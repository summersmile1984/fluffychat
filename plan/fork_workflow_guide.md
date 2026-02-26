# 维护自定义 FluffyChat 开发分支的最佳实践

如果你希望**基于 FluffyChat 开发自己的增值功能（比如 A2UI）**，并且**未来还能持续白嫖/合并 FluffyChat 官方的更新和 Bug 修复**，你需要建立一套标准的 Git Fork 工作流。

目前你的代码仓库绑定的 `origin` 是官方的仓库 (`https://github.com/krille-chan/fluffychat.git`)。我们需要将它变为一个真正的 "Fork" 项目。

---

## 步骤一：在 GitHub 上 Fork 项目
1. 去浏览器打开原始仓库：[krille-chan/fluffychat](https://github.com/krille-chan/fluffychat)。
2. 点击右上角的 **Fork** 按钮，将代码复制到你自己的 GitHub 账号下（例如 `your-username/fluffychat`）。

## 步骤二：改造你本地的 Git 仓库（重要）
现在的这一步，是要让你的本地代码库知道有两个远端仓库：
- `origin`（你自己的仓库，用来存你的自定义代码）
- `upstream`（FluffyChat 官方的仓库，用来拉取他们的最新代码）

在本地终端执行以下命令：
```bash
# 1. 把现在的 origin (官方仓库) 改名叫做 upstream
git remote rename origin upstream

# 2. 把你的独立 Fork 仓库设置为新的 origin
git remote add origin https://github.com/你的用户名/fluffychat.git

# 3. 推送你当前的代码到你自己的仓库，并建立追踪
git push -u origin main
```
> *注：FluffyChat 的主分支可能叫 `main`，具体看当前的默认分支名。如果是 `master` 就替换为 `master`。*

---

## 步骤三：开发自定义功能（按你自己的节奏）
**永远不要在主分支 (`main`) 上死磕或者直接魔改。**主分支应该保持干净，专门用来对齐官方的版本。

当你要开发 A2UI 时：
1. 切回主分支并确保它是最新的：
   `git checkout main`
2. 基于此创建一个属于你自己的功能分支：
   `git checkout -b feature/a2ui-integration`
3. 自由改代码，甚至可以大幅度重构 `message_content.dart`。改完后正常 `git add` 和 `git commit`。
4. 推送到你自己的仓库备份：
   `git push origin feature/a2ui-integration`

*(以后在这个分支上，想怎么改怎么改，改废了都不用怕！)*

---

## 步骤四：如何合并官方的更新？
过了 3 个月，FluffyChat 官方发布了修复性能的新版本，你想把这些更新吃进你的自定义代码里。

1. **获取官方的最新代码**：
   ```bash
   git fetch upstream
   ```
2. **更新你本地的主分支**：
   ```bash
   git checkout main
   git merge upstream/main  # 将官方最新的代码合并到你的 main 分支
   git push origin main     # 同步到你自己的 GitHub 备份
   ```
3. **把官方更新“注入”到你正在开发的 A2UI 分支中**：
   ```bash
   git checkout feature/a2ui-integration
   git merge main           # 把更新后的 main 融入你的自定义分支
   ```
   > ⚠️ **注意这里可能会有冲突（Merge Conflict）**：
   > 如果官方正好也改了 `message_content.dart`的同一个位置，Git 会提示冲突。你需要手动打开那个文件，保留你添加的 A2UI 逻辑，同时接纳官方的修复代码。这是所有二次开发不可避免的“手工税”。

---

## 高阶提示：如何减少未来的合并冲突？
既然你要按自己的节奏加特征，要尽量**避免“侵入式”修改**官方庞大的原始文件。

*   **隔离你的 UI**：比如上文提到的 [A2UI 方案](file:///Users/macstudio/.gemini/antigravity/brain/9c41aa76-b6fc-483d-b0fd-221a4fc6458f/a2ui_integration_plan.md)，建议你把 A2UIMessageCard 这个组件写在一个**全新的文件**（如 `lib/pages/chat/events/a2ui_card.dart`）里。
*   **最小化对接断点**：你在官方的逻辑（`message_content.dart`）里，**只加 3 行代码进行判断和跳转拦截**。
*   **收益**：如果官方后续把 `MessageContent` 重写了，由于你的核心 A2UI 逻辑都在独立文件里，因此合并冲突时你顶多修复那 3 行拦截代码，轻松愉快。
