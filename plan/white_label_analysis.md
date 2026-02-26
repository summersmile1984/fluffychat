# 白牌（White-Label）改造深度分析

> [!NOTE]
> 本文档包含 **6 个层面** 的分析。第六层（UI 字符串与代码内品牌引用）为本次补充的深入排查结果。

## 目标

让同一套 Flutter 代码库能够为不同客户/租户编译出完全独立的 App，每个版本拥有：
- 自己的 App 名称、图标、颜色
- 自己的 Bundle ID / Package Name（能独立上架应用商店）
- 自己的 Matrix Homeserver（或开放选择）
- 自己的推送通知（Firebase 项目、APNs 证书）
- 自己的隐私政策、支持链接等

> [!IMPORTANT]
> 白牌改造涉及 **5 个层面**，层层递进。最小代价是"仅改 Dart 层配置"，但完整上架需要同时改造**原生平台层**和**CI/CD 构建管道**。

---

## 第一层：Dart 配置层（改动最集中）

### 1.1 `lib/config/app_config.dart` — 全局常量中枢

这是**唯一需要逐产品改造的 Dart 常量文件**。当前存在大量硬编码的 FluffyChat 品牌信息：

| 常量 | 当前值 | 白牌化建议 |
|------|--------|-----------|
| `primaryColor` | `0xFF5625BA` | 改为构建参数注入 |
| `allowOtherHomeservers` | `false` | 按客户需求配置 |
| `deepLinkPrefix` | `im.fluffychat://chat/` | 每个 App 独立 URL Scheme |
| `pushNotificationsChannelId` | `fluffychat_push` | 每个客户独立频道 ID |
| `pushNotificationsAppId` | `chat.fluffy.fluffychat` | 每个客户独立 App ID |
| `website` / `sourceCodeUrl` etc. | fluffy.chat / FluffyChat GitHub | 替换为客户品牌链接 |
| `appId` / `appOpenUrlScheme` | `im.fluffychat.*` | 客户专属 Bundle ID |
| `homeserverList` URL | FluffyChat 官方 GitHub raw | 客户自己的服务器列表 |
| `privacyUrl` | fluffy.chat/privacy | 客户自己的隐私政策 |

**改造方案（方案 A：环境变量注入，推荐）**：

```dart
// lib/config/app_config.dart 改为从 Dart 定义常量读取
// 在运行期构建时通过 --dart-define 注入，例如：
// flutter build apk --dart-define=APP_NAME="企业通" --dart-define=PRIMARY_COLOR=0xFF2196F3

abstract class AppConfig {
  static const String appName =
      String.fromEnvironment('APP_NAME', defaultValue: 'Turning Agent');
  static const String defaultHomeserver =
      String.fromEnvironment('DEFAULT_HOMESERVER', defaultValue: 'matrix.org');
  static const int primaryColorValue =
      int.fromEnvironment('PRIMARY_COLOR', defaultValue: 0xFF5625BA);
  static const Color primaryColor = Color(primaryColorValue);

  // 推送相关（每个 App 必须独立）
  static const String pushNotificationsAppId =
      String.fromEnvironment('PUSH_APP_ID', defaultValue: 'chat.fluffy.fluffychat');
  static const String pushNotificationsChannelId =
      String.fromEnvironment('PUSH_CHANNEL_ID', defaultValue: 'fluffychat_push');
  static const String deepLinkPrefix =
      String.fromEnvironment('DEEP_LINK_PREFIX', defaultValue: 'im.fluffychat://chat/');
  // ...其余类似
}
```

**改造方案（方案 B：config.json，已有基础，适合 Web）**：

`setting_keys.dart` 已经实现了一套 Web 端的 `config.json` 运行时注入机制（参考第 88~117 行）。只需要在原生端打包前把一个 JSON 文件 bundle 进 APK/IPA，就能实现类似效果。

```json
// assets/config.json (每个白牌版本一个)
{
  "applicationName": "企业通",
  "defaultHomeserver": "chat.enterprise.com",
  "colorSchemeSeedInt": 16777215,
  "allowOtherHomeservers": false,
  "presetHomeserver": "chat.enterprise.com"
}
```

需要在原生端启动时读取（目前仅 Web 实现了，**原生端需要额外开发**）。

---

## 第二层：原生平台层（每个 App 必须独立）

### 2.1 Android

| 文件 | 白牌化内容 |
|------|-----------|
| `android/app/src/main/AndroidManifest.xml` | `android:label`（App 名）、Deep Link Scheme（`im.fluffychat`）、OIDC callback scheme |
| `android/app/build.gradle` | `applicationId`（Package Name，例如 `com.enterprise.chat`）、`versionName`、`versionCode` |
| `android/app/google-services.json` | Firebase 项目配置（**每个客户必须有自己的 Firebase 项目**） |
| `android/app/src/main/res/mipmap-*/` | App 图标 |
| `android/app/src/main/res/drawable-*/splash.png` | 启动屏 |
| `android/app/src/main/res/values/strings.xml` | 如有字符串资源 |

### 2.2 iOS / macOS

| 文件 | 白牌化内容 |
|------|-----------|
| `ios/Runner.xcodeproj/project.pbxproj` | Bundle Identifier、Signing Team |
| `ios/Runner/Info.plist` | `CFBundleDisplayName`（App 名）、URL Schemes |
| `ios/Runner/GoogleService-Info.plist` | APNs / Firebase 配置（已存在此文件！**每客户独立**） |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | App 图标（全套尺寸）|
| `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_NAME`、`PRODUCT_BUNDLE_IDENTIFIER` |
| `.entitlements` 文件 | `com.apple.developer.team-identifier` |

---

## 第三层：Assets 资源层

```
assets/
├── logo.png              ← 需替换（Chat list 顶部 Logo）
├── logo_transparent.png  ← 需替换
├── banner.png            ← 需替换（欢迎页展示）
├── banner_transparent.png ← 需替换（Intro 页大 Banner）
├── info-logo.png         ← 需替换
└── turning_agent_icon.png ← 需替换（启动页图标 Source）
```

`pubspec.yaml` 中有 `flutter_native_splash` 的配置（当前指向 `turning_agent_icon.png`）。每个白牌版本需要提供一套自己的图标。

---

## 第四层：推送通知基础设施（最复杂，必须独立）

这是白牌改造中**技术难度最高**的部分。

当前架构：
- Android：使用 Firebase FCM（需要 `google-services.json`）
- iOS：使用 APNs + optional Firebase（`GoogleService-Info.plist`）
- 统一通过 `AppConfig.pushNotificationsGatewayUrl` 把通知路由给 Matrix 推送服务

**每个白牌 App 需要**：
1. 自己的 **Firebase 项目**（含 FCM Server Key）
2. 自己的 **APNs 证书**（或者 APNs Auth Key）
3. 自己的 **推送网关服务器**（或共用你们的 SePushed/sygnal instance）

> [!WARNING]
> 白牌 App 如果共用同一个 Firebase 项目的 FCM 推送，所有客户的推送流量都会汇聚到同一个账户下，**这在商业上通常是不可接受的**（稳定性、隐私、计费）。必须为每个 B 端客户独立申请 Firebase 项目。

---

## 第五层：构建管道（CI/CD）

上述改造完成后，要快速出包给多个客户，**不能手动改文件**，需要建立一套参数化构建管道。

### 推荐目录结构

```
white_label_configs/
├── enterprise_a/
│   ├── config.dart          # Dart --dart-define 变量
│   ├── assets/              # 图标、Logo
│   ├── android/
│   │   └── google-services.json
│   └── ios/
│       └── GoogleService-Info.plist
├── enterprise_b/
│   └── ...
└── build.sh                 # 自动化构建脚本
```

### 核心构建脚本 `build.sh`

```bash
#!/bin/bash
TENANT=$1  # e.g. enterprise_a
CONFIG_DIR="white_label_configs/$TENANT"

# 1. 覆盖 Firebase 配置
cp "$CONFIG_DIR/android/google-services.json" android/app/
cp "$CONFIG_DIR/ios/GoogleService-Info.plist" ios/Runner/

# 2. 覆盖 assets
cp -r "$CONFIG_DIR/assets/" assets/

# 3. 构建（通过 --dart-define 注入品牌参数）
flutter build apk \
  --dart-define-from-file="$CONFIG_DIR/config.dart"
```

---

## 总结：工作量评估

| 层面 | 工作量 | 是否可复用 |
|------|--------|----------|
| Dart 配置层重构（`app_config.dart`）| 1-2天 | ✅ 一次改造，所有客户受益 |
| 原生平台层模板化（Manifest, xcconfig） | 2-3天 | ✅ 一次改造 |
| Assets 替换自动化脚本 | 1天 | ✅ |
| 推送基础设施（Firebase 申请、配置）| **每个客户 0.5天** | ❌ 每客户独立 |
| CI/CD 管道搭建（GitHub Actions）| 2-3天 | ✅ 一次搭建，每次新客户 30 分钟配置 |
| config.json 原生端支持（可选） | 1天 | ✅ |

---

## 第六层：UI 字符串与代码内部品牌引用（最容易忽视！）

这是用户最能实际感知到的一层，散落在各个 Dart 文件和本地化字符串中。

### 6.1 本地化字符串（`lib/l10n/intl_en.arb`）

| ARB Key | 问题内容 | 建议 |
|---------|---------|------|
| `inviteText` | `"...Visit fluffychat.im and install the app..."` — 邀请他人时发出的文字硬编码了 `fluffychat.im` 网址 | 改为 `AppConfig.website` 动态引用，或用 `{appName}` 占位符 |
| `newMessageInFluffyChat` | Key 名本身含 `FluffyChat`，显示文字已改为 "Turning Agent"，但 ARB key 名留着原样 | 重命名 key 为 `newMessageNotification` |
| `fluffychat` | Key 名和 App 名强耦合，虽已改值，但多语言 arb 文件（中文、俄文等）里该 key 可能仍是 "FluffyChat" | 检查并更新所有 `lib/l10n/intl_*.arb` |

### 6.2 URL/链接硬编码（Dart 源码中）

| 文件 | 行 | 内容 | 建议 |
|------|----|------|------|
| `lib/utils/sign_in_flows/oidc_login.dart` | 53 | `logoUri: Uri.parse('https://fluffy.chat/assets/favicon.png')` — OIDC 登录时对服务器展示的 App Logo 是 FluffyChat 的 | 改为指向 `AppConfig.website` 下的 logo |
| `lib/utils/fluffy_share.dart` | 39 | `'https://matrix.to/#/...?client=im.fluffychat'` — 用户分享个人 Matrix ID 时后缀带 FluffyChat 的 client 标识 | 改为 `AppConfig.appOpenUrlScheme` 之类的动态值 |
| `lib/widgets/matrix.dart` | ~410 | `'fluffychat-export-*.fluffybackup'` — 导出备份文件名硬编码 `fluffybackup` 扩展名 | 改用 `AppConfig.appName.toLowerCase() + '-backup'` |

### 6.3 Android 通知图标名（`lib/widgets/local_notifications_extension.dart`）

```dart
appIcon: 'fluffychat',   // 行 121
```
这个字符串对应 `android/app/src/main/res/drawable/fluffychat.png`（通知栏小图标的资源名）。每个白牌 App 需要：
1. 替换图标资源文件为自己的图标
2. 把这里的 `'fluffychat'` 字符串改为对应的资源文件名（例如 `'app_icon'`）

### 6.4 Matrix 事件命名空间（内部数据，影响互操作性）

这类引用是 **存储在 Matrix 服务器上的数据字段名**，改动有较高风险（会导致旧数据无法读取）：

| 文件 | 常量值 | 说明 |
|------|--------|------|
| `lib/utils/account_bundles.dart:46` | `'im.fluffychat.account_bundles'` | 多账号分组配置存储 Key |
| `lib/utils/account_config.dart:4` | `'im.fluffychat.account_config'` | 账号配置存储 Key |
| `lib/utils/client_manager.dart:23` | `'im.fluffychat.store.clients'` | 本地 SharedPreferences Key |
| `lib/pages/chat_list/chat_list.dart:157` | `'im.fluffychat.search.server'` | 搜索记录 Key |
| `lib/utils/event_checkbox_extension.dart:4` | `'im.fluffychat.checkboxes'` | 消息内 Checkbox 事件 Key |
| `lib/widgets/app_lock.dart:68` | `'chat.fluffy.app_lock'` | 本地 PIN lock 的 SharedPreferences Key |

> [!WARNING]
> 上述 Matrix 命名空间（`im.fluffychat.*`）和本地 SharedPreferences Key 如果改了，**历史数据会全部丢失**（多账号配置、Pin Lock 设置等）。白牌改造时推荐的策略是：**对 B 端客户的全新部署可以统一改**；对已有用户要写迁移代码。

### 6.5 内部 Dart 类名（不影响用户，但影响代码维护性）

以下类名含 `FluffyChat` 前缀，是纯代码组织问题，不直接影响用户：
- `FluffyChatPushPayload` / `FluffyChatNotificationActions`（`push_helper.dart`）
- `FluffyChatApp`（`fluffy_chat_app.dart`）
- `FluffyThemes`（`themes.dart`）

建议在白牌化重构时统一重命名为项目名前缀（例如 `AppPushPayload`）。

---

### 一键搜索命令（快速定位残留）

```bash
# 搜索所有用户可见的 FluffyChat 字样（排除 import 和注释）
grep -rn --include="*.dart" -i "fluffy" lib/ | \
  grep -v "import\|// \|package:fluffychat/\|FluffyChatApp\|FluffyThemes"

# 搜索 l10n 字符串中的品牌字样
grep -n "fluffy\|FluffyChat" lib/l10n/intl_en.arb | grep -v '"@'
```

---

---

## 第七层：UI 界面中的不适宜按钮和菜单项（用户直接可见）

这一层是最直接影响白牌客户体验的——用户点击后会跳转到 FluffyChat 自己的网站或捐款页面。

### 7.1 Donate（捐款）按钮 🔴 最高优先级

**位置**：主聊天列表页 → 左上角头像点击 → 弹出菜单

```dart
// lib/pages/chat_list/client_chooser_button.dart:72-82
if (Matrix.of(context).backgroundPush?.firebaseEnabled != true)
  PopupMenuItem(
    value: SettingsAction.support,
    child: Row(children: [
      const Icon(Icons.favorite, color: Colors.red),  // ❤️ 红心图标
      Text(L10n.of(context).donate),  // → 跳转 ko-fi.com/krille
    ]),
  ),
```

**修复**：删除此 `if` 块，或改为客户自己的"联系我们"入口。

---

### 7.2 About 对话框包含 Source Code 按钮 🔴

**位置**：设置页 → About → 弹出对话框

```dart
// lib/utils/platform_infos.dart:57-59
onPressed: () => launchUrlString(AppConfig.sourceCodeUrl),
// AppConfig.sourceCodeUrl = 'https://github.com/krille-chan/fluffychat'
```

**修复**：删除此按钮，或替换为客户自己的产品官网链接。

---

### 7.3 Privacy Policy 链接（两处）🟡

| 位置 | 文件 |
|------|------|
| 登录页右上角菜单 → Privacy | `intro_page.dart:61` |
| 设置页 → Privacy | `settings_view.dart:203` |

均跳转 `AppConfig.privacyUrl = https://fluffy.chat/en/privacy`。  
**修复**：通过 `--dart-define=PRIVACY_URL=...` 注入客户自己的隐私政策。

---

### 7.4 四处教程链接（全部指向 fluffy.chat FAQ）🟡

| 功能 | 文件 | 常量 |
|------|------|------|
| 贴纸教程 | `sticker_picker_dialog.dart:150` | `howDoIGetStickersTutorial` |
| 加密教程 | `chat_encryption_settings_view.dart:38` | `encryptionTutorial` |
| 新建私聊教程 | `new_private_chat_view.dart:40` | `startChatTutorial` |
| 推送通知教程 | 推送设置页 | `enablePushTutorial` |

**修复**：通过 `--dart-define` 注入客户自己的 FAQ URL，或直接删除跳转按钮。

---

### 7.5 Login 页 Support 链接（→ GitHub Issues）🟡

**位置**：`lib/widgets/layouts/login_scaffold.dart:125`

```dart
onPressed: () => launchUrlString(AppConfig.supportUrl),
// 目前跳转: https://github.com/krille-chan/fluffychat/issues
```

**修复**：改为客户自己的客服链接，或删除。

---

### 完整改动清单（按优先级）

| 优先级 | 元素 | 文件 | 操作 |
|--------|------|------|------|
| 🔴 P0 | Donate 按钮（红心图标）| `client_chooser_button.dart:72-82` | **删除** |
| 🔴 P0 | About 对话框 Source Code 按钮 | `platform_infos.dart:57-59` | **删除或替换** |
| 🔴 P0 | Login 页 Support 链接 | `login_scaffold.dart:125` | **替换为客户客服链接** |
| 🟡 P1 | 隐私政策链接（两处）| `settings_view.dart:203` / `intro_page.dart:61` | **--dart-define 注入** |
| 🟡 P1 | 四处教程链接 | 各自页面 | **--dart-define 注入或删除** |

---

> [!TIP]
> **最快的切入点**：先将 `app_config.dart` 改为 `--dart-define` 注入模式，再写一个 `build.sh`，就可以在不触碰原生文件的前提下，快速为不同客户改变 App 名称、颜色、默认服务器。这是 MVP 版本的白牌方案。

> [!IMPORTANT]
> **第七层是白牌化最紧迫的部分**。Donate 按钮和 Source Code 按钮必须在任何白牌版本交付给 B 端客户之前处理掉。
