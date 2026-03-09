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

    Logs().d('[A2UI] Raw type: ${raw.runtimeType}');

    try {
      final dynamic decoded;
      if (raw is String) {
        decoded = json.decode(raw);
        Logs().d('[A2UI] Decoded from JSON string, type: ${decoded.runtimeType}');
      } else {
        decoded = raw;
        Logs().d('[A2UI] Using raw value directly, type: ${decoded.runtimeType}');
      }

      if (decoded is List) {
        Logs().d('[A2UI] Parsing ${decoded.length} message(s)');
        final messages = <A2uiMessage>[];
        for (var i = 0; i < decoded.length; i++) {
          try {
            final item = decoded[i];
            Logs().d('[A2UI] Item[$i] keys: ${(item as Map?)?.keys.toList()}');
            final msg = A2uiMessage.fromJson(Map<String, dynamic>.from(item as Map));
            Logs().d('[A2UI] Item[$i] parsed OK: ${msg.runtimeType}');
            messages.add(msg);
          } catch (itemErr, itemStack) {
            Logs().e('[A2UI] Item[$i] FAILED: $itemErr', itemErr, itemStack);
            Logs().e('[A2UI] Item[$i] raw content: ${json.encode(decoded[i])}');
          }
        }
        return messages;
      } else if (decoded is Map) {
        Logs().d('[A2UI] Parsing single message, keys: ${decoded.keys.toList()}');
        return [A2uiMessage.fromJson(Map<String, dynamic>.from(decoded))];
      } else {
        Logs().w('[A2UI] Unexpected decoded type: ${decoded.runtimeType}');
      }
    } catch (e, stack) {
      Logs().e('[A2UI] Failed to parse a2ui_content: $e', e, stack);
    }

    return [];
  }
}
