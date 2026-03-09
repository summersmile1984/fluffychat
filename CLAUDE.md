# Turning Agent (Matrix Client) 项目须知

## 项目概览
这是一个基于 Flutter 的 Matrix 协议即时通信客户端，Fork 自 [krille-chan/fluffychat](https://github.com/krille-chan/fluffychat)，已完成白牌改造为 **Turning Agent** 品牌。

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
# origin  → https://github.com/summersmile1984/fluffychat
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

## 白牌（White-Label）架构

### 品牌目录结构
```
brands/
├── turning_agent/          # 当前品牌
│   ├── brand.json          # 所有品牌配置（标识符、URL、主题色、默认值）
│   └── assets/             # icon.png, logo.png, banner.png, favicon.png
└── _template/              # 新品牌模板
    ├── brand.json
    └── assets/.gitkeep
```

### 品牌切换命令
```bash
./scripts/apply-brand.sh turning_agent          # 应用品牌
./scripts/apply-brand.sh turning_agent --dry-run # 预览变更
./scripts/apply-brand.sh new_brand              # 切换到新品牌
cat .current_brand                               # 查看当前品牌
```

### 工作原理
- **`brand.json`**：品牌配置单一数据源（标识符、URL、主题色等）
- **`// @brand:xxx` 标记**：Dart 源文件中的标记注释，脚本定位到标记后替换下一行
- **`apply-brand.sh`**：读取 JSON → 替换 15+ 文件（8 个平台）→ 复制资源 → 运行 Flutter 再生

### 标记文件
| 文件 | 标记数 | 内容 |
|------|--------|------|
| `lib/config/app_config.dart` | 18 | 颜色、URL、标识符 |
| `lib/config/setting_keys.dart` | 4 | 推送网关、应用名、默认服务器、主题色 |
| `lib/utils/client_manager.dart` | 1 | 客户端命名空间 |

### 保留的 FluffyChat 引用（内部代码，非用户可见）
- `package:fluffychat` — Dart 包名（改动需全量重命名）
- `FluffyChatApp` 等类名 — 内部标识符
- `lib/l10n/l10n_*.dart` — 自动生成文件，key 名不影响显示

## 常用命令
```bash
flutter run -d macos                          # 运行 macOS 桌面版
flutter run -d chrome                          # 运行 Web 版
flutter build apk --debug                     # 构建 Android Debug APK
./scripts/apply-brand.sh <brand> [--dry-run]   # 品牌切换
```

## 规划文档（plan/ 目录）

| 文档 | 内容 |
|------|------|
| `plan/white_label_analysis.md` | 白牌改造深度分析（7 层），含所有品牌残留的定位和优先级清单 |
| `plan/a2ui_integration_plan.md` | A2UI 自定义消息格式接入方案 |
| `plan/architecture_overview.md` | 项目整体架构分析（四层结构、核心依赖） |
| `plan/fork_workflow_guide.md` | Fork 与上游合并工作流指南 |
