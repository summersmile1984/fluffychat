import 'package:genui/genui.dart';

import 'custom/custom_catalog.dart';

/// A2UI Widget Catalog Registry.
///
/// Merges GenUI's built-in CoreCatalogItems (18 standard A2UI components)
/// with any custom business-specific components.
///
/// Agent Bots can only use components registered in this catalog.
class A2uiCatalogRegistry {
  /// The complete catalog: core standard components + custom extensions.
  static Catalog get catalog {
    final coreCatalog = CoreCatalogItems.asCatalog();
    final customItems = CustomCatalog.all;
    if (customItems.isEmpty) return coreCatalog;
    return coreCatalog.copyWith(customItems);
  }
}
