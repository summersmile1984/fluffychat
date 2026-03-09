// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'package:genui/genui.dart';

/// A2UI HapticButton — a button that triggers device vibration on press.
///
/// Agent specifies the haptic intensity (light/medium/heavy) and the
/// action to trigger. The client uses Flutter's built-in HapticFeedback.

final _schema = S.object(
  properties: {
    'child': A2uiSchemas.componentReference(
      description: 'The ID of a child widget to display inside the button.',
    ),
    'action': A2uiSchemas.action(),
    'hapticType': S.string(
      description: 'Type of haptic feedback.',
      enumValues: ['light', 'medium', 'heavy', 'selection', 'vibrate'],
    ),
  },
  required: ['child', 'action'],
);

extension type _HapticButtonData.fromMap(JsonMap _json) {
  String get child => _json['child'] as String;
  JsonMap get action => _json['action'] as JsonMap;
  String get hapticType => (_json['hapticType'] as String?) ?? 'medium';
}

class A2uiHapticButton {
  static final CatalogItem item = CatalogItem(
    name: 'HapticButton',
    dataSchema: _schema,
    widgetBuilder: (itemContext) {
      final data = _HapticButtonData.fromMap(itemContext.data as JsonMap);
      final child = itemContext.buildChild(data.child);
      final actionName = data.action['name'] as String;

      return ElevatedButton(
        onPressed: () {
          // Trigger haptic feedback
          switch (data.hapticType) {
            case 'light':
              HapticFeedback.lightImpact();
            case 'heavy':
              HapticFeedback.heavyImpact();
            case 'selection':
              HapticFeedback.selectionClick();
            case 'vibrate':
              HapticFeedback.vibrate();
            default:
              HapticFeedback.mediumImpact();
          }
          // Dispatch action
          itemContext.dispatchEvent(
            UserActionEvent(
              name: actionName,
              sourceComponentId: itemContext.id,
              context: const {},
            ),
          );
        },
        child: child,
      );
    },
  );
}
