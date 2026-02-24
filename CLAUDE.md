# FluffyChat (Matrix Client) 项目须知

## 项目概览
这是一个基于 Flutter 的 Matrix 协议即时通信客户端，Fork 自 [krille-chan/fluffychat](https://github.com/krille-chan/fluffychat)。

## 核心架构（四层）

### Layer 1: UI 层 (`lib/pages/`, `lib/widgets/`)
- 路由：`go_router`，声明式导航
- 消息渲染入口：`lib/pages/chat/events/message_content.dart` — 通过 `switch (event.messageType)` 分发到不同的 Widget
- HTML 富文本渲染：`lib/pages/chat/events/html_message.dart`

### Layer 2: 状态管理层 (`lib/widgets/matrix.dart`, `lib/utils/`)
- **不使用** Redux / Bloc / Riverpod 等重型状态管理框架
- `Matrix` widget（`lib/widgets/matrix.dart`）通过 InheritedWidget 机制向下注入当前 `Client` 实例
- 访问方式：`Matrix.of(context).client`
- 多账号管理：`ClientManager`（`lib/utils/client_manager.dart`）维护 `List<Client>`，通过 `SharedPreferences` 持久化账号列表
- 多账号 UI 入口：`ClientChooserButton`（`lib/pages/chat_list/client_chooser_button.dart`）

### Layer 3: SDK & 数据层
- **核心 SDK 是纯 Dart 实现**：`package:matrix`（[famedly/matrix-dart-sdk](https://github.com/famedly/matrix-dart-sdk)），**不是**官方的 matrix-rust-sdk
- **Rust 唯一介入点**：端到端加密库 `flutter_vodozemac`，通过 FFI 调用 Rust 编写的 vodozemac 密码学引擎
- **数据库**：`sqflite_common_ffi` + `sqlcipher_flutter_libs`，SQLite 数据库使用 SQLCipher 全盘加密
- **数据库密钥**：通过 `flutter_secure_storage` 存储在系统 Keychain/Keystore 中（见 `lib/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart`）
- **依赖注入设计**：`ClientManager` 初始化时将 `NativeImplementationsIsolate`（后台加密线程）和 `flutterMatrixSdkDatabaseBuilder`（SQLite 配置）作为参数注入给 SDK

### Layer 4: 平台 & 后台层
- 后台推送通知通过 Isolate 处理
- 主入口：`lib/main.dart`

## macOS 本地开发注意事项

> ⚠️ **关键问题**：macOS 本地开发构建存在 Keychain 访问限制

- `flutter_secure_storage` 在未正确配置 Apple Developer 签名的本地构建中会抛出 `PlatformException(Code: -34018)` 错误
- **不要**在 `.entitlements` 文件中留空的 `keychain-access-groups` 数组
- `lib/widgets/app_lock.dart` 中的 `FlutterSecureStorage().write()` 已包裹 try-catch 防止启动崩溃
- `lib/pages/bootstrap/bootstrap_dialog.dart` 中密钥验证流程已添加 10 秒超时防止无限 Loading
- 历史消息无法解密是 Keychain 权限问题导致，非代码 Bug

## 自定义消息格式扩展（如 A2UI）

添加新消息类型的关键修改点：
1. **新建 Widget 文件**：`lib/pages/chat/events/` 目录下创建独立的渲染组件
2. **拦截渲染层**：在 `lib/pages/chat/events/message_content.dart` 的 `build()` 方法中添加判断拦截（推荐在 `switch` 语句前检查 `event.content` 中的自定义字段）
3. **发送逻辑**：调用 `room.sendEvent()` 并在 content map 中携带自定义字段
4. **向后兼容**：推荐使用 `msgtype: "m.text"` + 额外自定义字段（如 `org.google.a2ui`）的 Fallback 机制，确保其他客户端不会崩溃

## Fork 维护工作流

```bash
# 远端配置
# origin  → 你自己的 Fork 仓库
# upstream → https://github.com/krille-chan/fluffychat.git (官方)

# 同步官方更新
git fetch upstream
git checkout main
git merge upstream/main
git push origin main

# 将更新注入功能分支
git checkout feature/你的功能
git merge main
```

**减少合并冲突的原则**：自定义功能代码写在独立的新文件中，对官方文件的修改控制在最少的拦截行数内。

## 常用命令
```bash
flutter run -d macos          # 运行 macOS 桌面版
flutter run -d chrome          # 运行 Web 版
flutter build apk --debug     # 构建 Android Debug APK
```
