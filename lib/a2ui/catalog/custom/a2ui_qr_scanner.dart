// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'package:genui/genui.dart';

/// A2UI QrScanner — displays a button to launch the QR code scanner.
///
/// When the user taps the button, the device camera opens to scan
/// a QR code. The scanned result is dispatched back to the Agent.
///
/// Note: qr_code_scanner_plus is already a project dependency.
/// The actual scanner page is opened via navigation to keep this
/// widget framework-agnostic.

final _qrSchema = S.object(
  properties: {
    'label': A2uiSchemas.stringReference(
      description: 'Button label text',
    ),
    'action': A2uiSchemas.action(),
  },
  required: ['action'],
);

class A2uiQrScanner {
  static final CatalogItem item = CatalogItem(
    name: 'QrScanner',
    dataSchema: _qrSchema,
    widgetBuilder: (itemContext) {
      final data = itemContext.data as JsonMap;
      final labelMap = data['label'] as Map?;
      final label = labelMap?['literalString'] as String? ?? 'Scan QR Code';
      final actionData = data['action'] as JsonMap;

      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(label),
          onPressed: () {
            // Dispatch action — the app's navigation layer handles
            // opening the QR scanner page. The scanned result can be
            // sent back via the action event context.
            itemContext.dispatchEvent(
              UserActionEvent(
                name: actionData['name'] as String,
                sourceComponentId: itemContext.id,
                context: const {'request': 'open_qr_scanner'},
              ),
            );
          },
        ),
      );
    },
  );
}
