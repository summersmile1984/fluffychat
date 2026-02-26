# 系统架构概览 (System Architecture Overview)

FluffyChat (Turning Agent) 是一个基于 Flutter 和 Matrix 协议的去中心化加密即时通讯客户端。经过代码仓库分析，它的整体架构可以自上而下分为 **四个主要层次**，它们通过依赖注入和响应式事件流（Streams）紧密配合：

## 1. 表现层 / UI 层 (UI Layer)
位于 `lib/pages/`（全屏页面）和 `lib/widgets/`（可复用组件）目录下。

*   **职责**：负责所有的视觉呈现和用户交互。
*   **路由机制**：使用 `go_router` (`config/routes.dart`) 进行声明式、基于 URL 的页面跳转。
*   **UI 响应**：不维护核心业务状态，而是通过 `StreamBuilder` 和 `FutureBuilder` 监听底层状态的变化并即时刷新（例如当收到新消息时，Stream 会触发 UI 重绘）。
*   **主题与适老化**：通过 `ThemeBuilder` 和 `FluffyThemes` 动态适配系统的亮暗模式以及 Material 3 取色功能。

## 2. 状态管理与业务逻辑层 (State Management & Logic Layer)
位于 `lib/utils/` 目录以及 `lib/widgets/matrix.dart`。

这一层的主要目标是**衔接 UI 和 SDK**，以及**维护多账号生命周期**。它摒弃了繁重的状态管理库（没有使用 Redux、Bloc 或 GetX），而是采用了 **“依赖注入 (Provider) + 响应式数据流 (Streams)”** 的极简思路。

*   **多账号管理器 (`ClientManager`)**：
    *   位于 `lib/utils/client_manager.dart`。它是全局的账号大管家。
    *   启动时，它会读取本地 `SharedPreferences` 中的账号列表，并为每个账号实例化一个原生的 `Client` 对象。
    *   如果应用支持后台推送，它也会在这里注册回调，确保当通知到来时，能唤醒对应的实例。
*   **状态注入 (`Matrix` Widget)**：
    *   位于 `lib/widgets/matrix.dart`。这是一个包裹在应用最外层的自定义跨组件依赖注入容器（基于 `InheritedWidget`）。
    *   它维护着一个 `List<Client>`，代表所有登录的账户。同时它对外暴露了当前活跃的账号 (`activeClient`)。
    *   所有的 UI 页面（如 `chat_list.dart`）只需要通过 `Matrix.of(context).client` 就能立刻拿到当前账号的上下文，并直接调用业务逻辑或监听数据流。

## 3. 核心通信与数据层 (SDK & Data Layer)
主要由 `package:matrix` (Matrix Dart SDK) 本身以及本地持久化扩展构成。这是最重的一层，几乎处理了所有的计算密集型和 I/O 密集型任务。

*   **真正的 SDK 选型与封装**：
    *   **协议通信**：严格来说，这个项目**并没有**完整使用官方的 `matrix-rust-sdk`，而是使用了一套由开源社区（如 FluffyChat 团队维护）的**纯 Dart 原生实现的 Matrix SDK** (`package:matrix`)。所有 HTTP 请求解析和协议状态机都是用 Dart 写的。
*   **唯一的 Rust 介入点（端到端加密）**：
    *   整个系统中唯一使用 Rust 的地方是 **密码学库 (`vodozemac`)**。Dart 原生的矩阵库通过 `flutter_vodozemac` 插件将这部分核心加密逻辑通过 **FFI（外部函数接口）** 交由底层的 Rust 共享库执行。这也是为什么你在本地开发时涉及到密钥相关操作非常容易崩溃（因为跨语言的数据结构共享涉及复杂的 C-FFI 边界和原生系统的安全存储权限）。
*   **平台能力的封装下沉**：
    *   为了保持 Dart SDK 本身的纯洁性并兼容桌面/Web 多端，应用在 `ClientManager` 初始化时将原生平台能力（如：`NativeImplementationsIsolate`，用来跑加密算法的子线程）以及 `flutterMatrixSdkDatabaseBuilder`（SQLite 配置）作为参数**注入（依赖注入）** 给 SDK，从而实现了业务逻辑对底层原生存储的优秀封装。

## 4. 平台与后台服务层 (Platform & Background Layer)
处理与 Android/iOS/macOS 原生系统的深度交互。

*   **多线程机制 (Isolates)**：在 `lib/main.dart` 中可以看到，应用启动时会分配后台 `Isolate` (独立线程)。这使得在后台处理大量同步数据或解密任务时，不会导致 UI 界面卡顿。
*   **后台推送机制 (Background Push)**：通过 `BackgroundPush` 和 `NotificationBackgroundHandler` 在 App 被杀掉 (Detached) 的情况下，依然能够在后台悄悄唤醒 Flutter 引擎来接收和解密消息，并通过 `flutter_local_notifications` 弹出通知。

---

## 互相之间如何配合？（数据流向）
1. **初始化**：`main.dart` 启动时，`ClientManager` 会从本地数据库读取所有保存的账号密码，初始化底层的 `Matrix Client`。
2. **事件流**：`Client` 开始在后台执行 `sync()` 轮询服务器数据。服务器返回的数据会被 `Client` 解析并落盘到 SQLite，随后通过 `client.onSync.stream` 广播出来。
3. **UI 渲染**：`chat_list.dart` 里的 `StreamBuilder` 监听到同步事件，触发 Flutter 重绘页面，显示最新的聊天列表。
4. **用户交互**：用户点击发送消息，触发 UI 函数 -> 调用 `Matrix.of(context).client.postMessage()` -> 底层 SDK 调用 `vodozemac` 进行端到端加密 -> 最终发送 HTTP 请求给服务器。
