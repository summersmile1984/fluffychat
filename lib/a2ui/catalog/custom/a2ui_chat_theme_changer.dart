// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'package:genui/genui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A2UI ChatThemeChanger — allows Agent to present theme/background options.
///
/// The Agent provides a list of color themes or wallpaper URLs.
/// The user selects one, and it's persisted to SharedPreferences.

final _themeSchema = S.object(
  properties: {
    'title': A2uiSchemas.stringReference(
      description: 'Title text for the theme picker',
    ),
    'options': S.list(
      description: 'Available theme options',
      items: S.object(
        properties: {
          'name': S.string(description: 'Option display name'),
          'colorHex': S.string(description: 'Hex color string, e.g. #FF5722'),
          'wallpaperUrl': S.string(description: 'Optional wallpaper image URL'),
        },
        required: ['name'],
      ),
    ),
    'action': A2uiSchemas.action(),
  },
  required: ['options', 'action'],
);

class A2uiChatThemeChanger {
  static final CatalogItem item = CatalogItem(
    name: 'ChatThemeChanger',
    dataSchema: _themeSchema,
    widgetBuilder: (itemContext) {
      final data = itemContext.data as JsonMap;
      final titleMap = data['title'] as Map?;
      final title = titleMap?['literalString'] as String? ?? 'Choose a theme';
      final options = (data['options'] as List?) ?? [];
      final actionData = data['action'] as JsonMap;

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style:
                    Theme.of(itemContext.buildContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options.map((opt) {
                  final option = opt as Map;
                  final name = option['name'] as String? ?? '';
                  final colorHex = option['colorHex'] as String?;
                  final wallpaperUrl = option['wallpaperUrl'] as String?;

                  Color? color;
                  if (colorHex != null) {
                    var hex = colorHex.replaceFirst('#', '');
                    if (hex.length == 6) hex = 'FF$hex';
                    final value = int.tryParse(hex, radix: 16);
                    if (value != null) color = Color(value);
                  }

                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      // Persist the theme choice
                      final prefs = await SharedPreferences.getInstance();
                      if (colorHex != null) {
                        await prefs.setString('chat_color_scheme_seed', colorHex);
                      }
                      if (wallpaperUrl != null) {
                        await prefs.setString('chat_wallpaper', wallpaperUrl);
                      }

                      // Dispatch action back to Agent
                      final actionContext = <String, Object?>{
                        'selectedTheme': name,
                      };
                      if (colorHex != null) {
                        actionContext['colorHex'] = colorHex;
                      }
                      if (wallpaperUrl != null) {
                        actionContext['wallpaperUrl'] = wallpaperUrl;
                      }
                      itemContext.dispatchEvent(
                        UserActionEvent(
                          name: actionData['name'] as String,
                          sourceComponentId: itemContext.id,
                          context: actionContext,
                        ),
                      );
                    },
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: color ?? Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                        image: wallpaperUrl != null
                            ? DecorationImage(
                                image: NetworkImage(wallpaperUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 2, horizontal: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    },
  );
}
