import 'dart:convert';

import 'package:genui/genui.dart';
import 'package:matrix/matrix.dart';

/// Parses A2UI content from a Matrix Event.
///
/// Extracts the `a2ui_content` field from the event's content
/// and converts it into GenUI [A2uiMessage] objects that can be
/// processed by [A2uiMessageProcessor].
class A2uiEventParser {
  /// Check if an event contains A2UI content.
  static bool hasA2uiContent(Event event) {
    return event.content['a2ui_content'] != null;
  }

  /// Parse A2UI messages from a Matrix event.
  ///
  /// The `a2ui_content` field can be:
  /// - A single A2UI message (Map)
  /// - A list of A2UI messages (List<Map>)
  /// - A JSON string of the above
  ///
  /// Returns a list of [A2uiMessage] objects ready for processing.
  static List<A2uiMessage> parseMessages(Event event) {
    final raw = event.content['a2ui_content'];
    if (raw == null) return [];

    try {
      final dynamic decoded;
      if (raw is String) {
        decoded = json.decode(raw);
      } else {
        decoded = raw;
      }

      if (decoded is List) {
        return decoded
            .map((item) =>
                A2uiMessage.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      } else if (decoded is Map) {
        return [A2uiMessage.fromJson(Map<String, dynamic>.from(decoded))];
      }
    } catch (e) {
      Logs().w('[A2UI] Failed to parse a2ui_content: $e');
    }

    return [];
  }
}
