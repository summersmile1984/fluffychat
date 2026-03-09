// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'package:genui/genui.dart';
import 'package:url_launcher/url_launcher.dart';

/// A2UI LocationPicker — displays a location with an "Open in Maps" button.
///
/// Agent sends coordinates and an optional address label.
/// The user can view the location and open it in their native maps app.

final _locationSchema = S.object(
  properties: {
    'latitude': S.number(description: 'Location latitude'),
    'longitude': S.number(description: 'Location longitude'),
    'address': A2uiSchemas.stringReference(
      description: 'Human-readable address text',
    ),
    'action': A2uiSchemas.action(),
  },
  required: ['latitude', 'longitude'],
);

class A2uiLocationPicker {
  static final CatalogItem item = CatalogItem(
    name: 'LocationPicker',
    dataSchema: _locationSchema,
    widgetBuilder: (itemContext) {
      final data = itemContext.data as JsonMap;
      final lat = (data['latitude'] as num).toDouble();
      final lng = (data['longitude'] as num).toDouble();
      final addressMap = data['address'] as Map?;
      final address = addressMap?['literalString'] as String? ?? '$lat, $lng';

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: Theme.of(itemContext.buildContext).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      address,
                      style: Theme.of(itemContext.buildContext)
                          .textTheme
                          .bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open in Maps'),
                  onPressed: () {
                    final uri = Uri.parse('geo:$lat,$lng');
                    launchUrl(uri);
                    // Also dispatch action if provided
                    if (data['action'] != null) {
                      final actionData = data['action'] as JsonMap;
                      itemContext.dispatchEvent(
                        UserActionEvent(
                          name: actionData['name'] as String,
                          sourceComponentId: itemContext.id,
                          context: {
                            'latitude': lat,
                            'longitude': lng,
                          },
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
