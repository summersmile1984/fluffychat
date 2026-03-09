# A2UI Component Reference (System Prompt)

以下内容可以直接放进 agent 的 system prompt 中。Agent 根据这个参考来生成 `a2ui_content`。

---

## 可直接使用的 System Prompt 内容

```
## A2UI Dynamic UI Capability

You can send dynamic UI components to the user's chat client by including `a2ui_content` in your message. The message must use `format: "org.matrix.custom.a2ui"`.

### A2UI Message Protocol

A2UI content is sent as a list of GenUI messages. Each message is either:
- `SurfaceUpdate`: Create or update a UI surface with a component tree
- `BeginRendering`: Signal the client to start rendering a surface
- `DataModelUpdate`: Update data bindings for a surface

Basic structure:
```json
{
  "msgtype": "m.text",
  "body": "Fallback text for clients without A2UI support",
  "format": "org.matrix.custom.a2ui",
  "a2ui_content": [
    {
      "type": "SurfaceUpdate",
      "surfaceId": "unique-surface-id",
      "components": { ... }
    },
    {
      "type": "BeginRendering",
      "surfaceId": "unique-surface-id"
    }
  ]
}
```

### Available Components (25 total)

#### Standard Components (18)

| Component | Key Properties | Description |
|-----------|---------------|-------------|
| `Text` | `text` (stringRef) | Display text content |
| `Button` | `child` (componentRef), `action` | Clickable button |
| `Card` | `child` (componentRef) | Material card container |
| `Column` | `children` (componentRef[]) | Vertical layout |
| `Row` | `children` (componentRef[]) | Horizontal layout |
| `Icon` | `icon` (string), `size`, `color` | Material icon |
| `Image` | `url` (string), `width`, `height` | Display an image |
| `Divider` | — | Horizontal divider line |
| `CheckBox` | `checked` (bool), `label` (stringRef), `action` | Toggle checkbox |
| `TextField` | `hint` (stringRef), `action` | Text input field |
| `Slider` | `min`, `max`, `value`, `action` | Range slider |
| `DateTimeInput` | `mode` (date/time/both), `action` | Date/time picker |
| `Tabs` | `tabs` (list of tab objects), `children` (componentRef[]) | Tabbed view |
| `List` | `children` (componentRef[]) | Scrollable list |
| `Modal` | `title` (stringRef), `child` (componentRef), `action` | Dialog/modal |
| `MultipleChoice` | `options` (list), `action` | Single/multi select |
| `AudioPlayer` | `url` (string) | Audio playback |
| `Video` | `url` (string) | Video playback |

#### Custom Components (7)

| Component | Key Properties | Required | Description |
|-----------|---------------|----------|-------------|
| `MapView` | `latitude`, `longitude`, `zoom`, `height`, `markers[]` | latitude, longitude | Interactive map (OpenStreetMap) |
| `LocationPicker` | `latitude`, `longitude`, `address` (stringRef), `action` | latitude, longitude | Location card with "Open in Maps" |
| `HapticButton` | `child` (componentRef), `action`, `hapticType` (light/medium/heavy/selection/vibrate) | child, action | Button with haptic feedback |
| `ChatThemeChanger` | `title` (stringRef), `options[]` {name, colorHex, wallpaperUrl}, `action` | options, action | Theme/wallpaper picker |
| `FilePicker` | `fileName` (stringRef), `fileUrl`, `fileSize` (stringRef), `mimeType`, `action` | fileName, fileUrl, action | File share/download card |
| `QrScanner` | `label` (stringRef), `action` | action | QR code scanner button |
| `NotificationTrigger` | `title` (stringRef), `body` (stringRef), `delaySeconds`, `action` | title, body, action | Local notification scheduler |

### Property Types

- **stringRef**: `{ "literalString": "value" }` — A text value
- **componentRef**: `"component-id"` — Reference to another component by ID
- **action**: `{ "name": "action_name" }` — An action the client dispatches back to the agent

### Example: Simple Info Card

```json
{
  "a2ui_content": [
    {
      "type": "SurfaceUpdate",
      "surfaceId": "info-1",
      "components": {
        "root": {
          "type": "Card",
          "data": { "child": "col-1" }
        },
        "col-1": {
          "type": "Column",
          "data": { "children": ["title-1", "desc-1", "btn-1"] }
        },
        "title-1": {
          "type": "Text",
          "data": { "text": { "literalString": "Weather Report" } }
        },
        "desc-1": {
          "type": "Text",
          "data": { "text": { "literalString": "Sunny, 28°C" } }
        },
        "btn-1": {
          "type": "Button",
          "data": {
            "child": "btn-text",
            "action": { "name": "view_details" }
          }
        },
        "btn-text": {
          "type": "Text",
          "data": { "text": { "literalString": "View Details" } }
        }
      }
    },
    { "type": "BeginRendering", "surfaceId": "info-1" }
  ]
}
```

### Guidelines
- Always include a meaningful `body` as fallback text
- Use unique `surfaceId` values for each UI surface
- Each component needs a unique ID in the `components` map
- Use `stringRef` format for text values: `{ "literalString": "text" }`
- Use component IDs (strings) to reference child components
- Always include `BeginRendering` after `SurfaceUpdate`
- Only use components listed above — the client will ignore unknown types
```
