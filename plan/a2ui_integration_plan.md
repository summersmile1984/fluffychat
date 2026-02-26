# Google A2UI (Adaptive Audio UI) 消息格式集成方案

在当前的 FluffyChat (基于 Dart Matrix SDK) 架构中，要想让系统支持一个非标准的全新消息格式（例如 `a2ui` 的结构化音频交互卡片），需要从**协议定义**和**UI 渲染**两个层面入手。

以下是两种可行的技术方案：

---

## 方案一：兼容型方案（推荐，向前兼容老客户端）
利用 Matrix 规范中推荐的 **"Fallback（回退）机制"**。我们将 a2ui 消息包装成一个普通的富文本 (`m.text`) 消息，但携带自定义的扩展字段。

1.  **协议层的发送改造（拦截发送逻辑）**：
    发出的原始 JSON 结构如下：
    ```json
    {
      "type": "m.room.message",
      "content": {
        "msgtype": "m.text",
        "body": "[A2UI 语音卡片 - 请升级您的客户端查看]", 
        "format": "org.matrix.custom.html",
        "formatted_body": "<div data-a2ui='true'>...</div>",
        "org.google.a2ui": {
           // 这里放置 A2UI 的结构化 JSON 数据
           "audio_url": "mxc://...",
           "transcript": "你好",
           "actions": [...]
        }
      }
    }
    ```
2.  **UI 层的渲染改造（修改 `MessageContent`）**：
    在 `lib/pages/chat/events/message_content.dart` 中的 `build` 方法里，我们在解析 `MessageTypes.Text` 时加入判断逻辑：
    ```dart
    // message_content.dart 里面增加拦截
    if (event.content['org.google.a2ui'] != null) {
      // 提取 json，返回我们自己写的 A2UI 组件
      return A2UIMessageCard(
        a2uiData: event.content['org.google.a2ui'], 
        event: event,
      );
    }
    ```
    优势：其他不支持 A2UI 的普通 Matrix 客户端（比如 Element）仍能看到 `body` 中的文本内容("[A2UI 语音卡片...]")，不会报错。

---

## 方案二：激进型方案（自定义 MsgType）
彻底抛弃向后兼容，创建一个专属的 Message Type。

1.  **自定义 MsgType 标识**：
    设定一个新的 `msgtype` 为 `org.google.a2ui.message`。
    发送出的 JSON 如下：
    ```json
    {
      "type": "m.room.message",
      "content": {
        "msgtype": "org.google.a2ui.message",
        "audio_url": "mxc://...",
        "transcript": "你好"
      }
    }
    ```
2.  **修改 `MessageContent` 的 Switch 路由**：
    在 `lib/pages/chat/events/message_content.dart` 的 `switch (event.messageType)` 语句中，添加一条 `case` 分支：
    ```dart
    switch (event.messageType) {
      // 原来的 case
      case MessageTypes.Image: 
         /// ...
      
      // 新增自定义类型的拦截
      case 'org.google.a2ui.message':
         return A2UIMessageCard(event: event);
         
      default: 
         // ...
    }
    ```
    劣势：对于其他未经修改的 Matrix 客户端，遇到未知的 `msgtype`，它们会直接渲染为 `Label: "User sent unknown event"` 并且显示一个问号图标。

---

## 总结：该怎么做？

1. **新建 UI Widget**：在 `lib/pages/chat/events/` 目录下创建一个新的文件（例如 `a2ui_message.dart`），利用 Flutter 编写 A2UI 卡片的 UI。
2. **修改渲染层**：打开 `lib/pages/chat/events/message_content.dart`，拦截并返回刚刚写的 Widget。
3. **改造发送层**：在键盘/语音输入区域的发送逻辑处，构造出包含 `org.google.a2ui` 字段的 `Map<String, dynamic>`，然后调用 `Matrix.of(context).client.getRoomById(roomId).sendEvent('m.room.message', contentMap)` 发送给服务器。
