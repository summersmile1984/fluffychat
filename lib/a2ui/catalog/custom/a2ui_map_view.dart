// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:genui/genui.dart';
import 'package:latlong2/latlong.dart';

/// A2UI MapView — displays an interactive map centered on given coordinates.
///
/// Uses flutter_map (already in project dependencies) to render a map
/// with optional markers. Agent can set center, zoom, and marker positions.

final _mapSchema = S.object(
  properties: {
    'latitude': S.number(description: 'Center latitude'),
    'longitude': S.number(description: 'Center longitude'),
    'zoom': S.number(description: 'Zoom level (1-18)'),
    'height': S.number(description: 'Map height in pixels'),
    'markers': S.list(
      description: 'List of markers to display',
      items: S.object(
        properties: {
          'latitude': S.number(),
          'longitude': S.number(),
          'label': S.string(),
        },
        required: ['latitude', 'longitude'],
      ),
    ),
  },
  required: ['latitude', 'longitude'],
);

class A2uiMapView {
  static final CatalogItem item = CatalogItem(
    name: 'MapView',
    dataSchema: _mapSchema,
    widgetBuilder: (itemContext) {
      final data = itemContext.data as JsonMap;
      final lat = (data['latitude'] as num).toDouble();
      final lng = (data['longitude'] as num).toDouble();
      final zoom = (data['zoom'] as num?)?.toDouble() ?? 13.0;
      final height = (data['height'] as num?)?.toDouble() ?? 200.0;
      final markersList = (data['markers'] as List?) ?? [];

      final markers = markersList.map((m) {
        final marker = m as Map;
        return Marker(
          point: LatLng(
            (marker['latitude'] as num).toDouble(),
            (marker['longitude'] as num).toDouble(),
          ),
          child: const Icon(Icons.location_on, color: Colors.red, size: 36),
        );
      }).toList();

      // Always add center point as a marker if no markers provided
      if (markers.isEmpty) {
        markers.add(
          Marker(
            point: LatLng(lat, lng),
            child: const Icon(Icons.location_on, color: Colors.red, size: 36),
          ),
        );
      }

      return SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FlutterMap(
            options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: zoom),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
        ),
      );
    },
  );
}
