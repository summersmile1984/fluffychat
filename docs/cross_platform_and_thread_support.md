# FluffyChat 跨平台架构及 Thread 功能增强分析

## 一、跨平台支持概览

项目作为一个 Flutter 应用，支持 **6 个主流平台** 及 Ubuntu Snap：

- **Android / iOS**：原生级别支持。通过统一的 Dart 接口处理权限、推送、存储和本地相关 API。
- **macOS / Linux / Windows**：支持完善。使用 FFI 接入部分 C/C++ 依赖，同时支持桌面特性如系统托盘、拖放等。
- **Web**：使用 Flutter Web (部分功能受限，如受浏览器的安全性和 API 限制引发的录音格式局限)。

### OS 相关核心库多端支持情况：

- **推送通知**：Android/iOS (FCM/UnifiedPush/APNs)。桌面无原生全链路推送体验。
- **持久化与数据库**：Web 端由于无原生 sqlite/加密存储能力而受限于 IndexedDB 的轻量化支持。
- **系统相机与麦克风**：Web 和桌面由于缺少 `image_picker` 原生对接往往使用 HTML 获取，其他端能力完善。
- **加密体系**：端到端加密核心使用 `vodozemac`（Rust实现），全面覆盖所有平台（含 WASM 方案的 Web）。

---

## 二、布局 (Layout) 与 导航 (Navigation) 架构

### 2.1 导航：`go_router` 方案
- 结构清晰。具有认证守护（Redirect），区分登录态与非登录态。
- 关键节点包含重定向逻辑，保障页面状态可靠跳转。

### 2.2 响应式布局
采用**多栏布局**策略自适应宽屏和窄屏设计，不局限于平台而是通过屏幕宽度判断。
- `< 840px`：移动设备展现，页面间滑动推入（`MaterialPage`）。
- `> 840px`：双栏并行展现（`TwoColumnLayout`），基于无过渡的直接呈现逻辑。
- `> 1330px`：支持超大屏幕的拓展显示（预留给详情、Thread 等右侧第三列）。

---

## 三、Thread 局限性分析及优化

在修改前，我们识别到了两个影响用户体验（特别是桌面端）的 **Thread 局限性**。

### 1. 桌面端 Thread 遮挡主聊天视图（无侧边栏）

**背景**：不论屏幕多宽，点击回复打开 Thread 列表时，它一直采用与移动端相同的逻辑在当前路由原位遮蔽掉主聊天视图。
**修复**：在双栏或三栏布局下，利用 `FluffyThemes.isColumnMode` 挂载 `ChatThreadPanel`。将 Thread 会话显示为类似于 `ChatDetails` 的右侧内联悬浮/右吸附窗口。

*涉及文件：* 
- 新增 `lib/pages/chat/chat_thread_panel.dart` 提供桌面独有的 Thread 侧边栏布局展示。
- 修改 `lib/pages/chat/chat.dart` 以支持第三栏展示 `ChatThreadPanel`。
- 修改 `lib/pages/chat/chat_view.dart` 阻断全屏覆盖响应。

### 2. Thread 视图无法加载历史记录

**背景**：`chat_event_list.dart` 中为了限制复杂逻辑，当 `activeThreadId != null` 时不展示"加载更多历史记录"。
**修复**：解除历史按钮关于激活 Thread ID 是否为空的锁定，并通过按 `threadId` 过滤后的消息组数量，重新计算请求上拉历史消息的触发阈值，使 Thread 内部平滑支持历史消息追溯请求。

*涉及文件：*
- 修改 `lib/pages/chat/chat_event_list.dart`，移除短路条件并追加 `ignoreThread` 参数适配右侧视图。
