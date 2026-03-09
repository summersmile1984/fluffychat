import 'package:genui/genui.dart';

import 'a2ui_chat_theme_changer.dart';
import 'a2ui_file_picker.dart';
import 'a2ui_haptic_button.dart';
import 'a2ui_location_picker.dart';
import 'a2ui_map_view.dart';
import 'a2ui_notification_trigger.dart';
import 'a2ui_qr_scanner.dart';

/// Custom A2UI catalog items for domain-specific components.
///
/// These components extend the standard A2UI catalog with device-specific
/// capabilities: haptic feedback, maps, location, file sharing, QR scanning,
/// theme customization, and local notifications.
///
/// To add a new custom component:
/// 1. Create a new file in this directory (e.g., `a2ui_my_widget.dart`)
/// 2. Define a `CatalogItem` using `S.object()` for schema and `widgetBuilder`
/// 3. Add the item to the list below
class CustomCatalog {
  static List<CatalogItem> get all => [
        A2uiHapticButton.item,
        A2uiMapView.item,
        A2uiLocationPicker.item,
        A2uiChatThemeChanger.item,
        A2uiFilePicker.item,
        A2uiQrScanner.item,
        A2uiNotificationTrigger.item,
      ];
}
