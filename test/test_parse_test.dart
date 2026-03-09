import 'package:matrix/matrix.dart';
import 'package:fluffychat/a2ui/bridge/a2ui_event_parser.dart';
import 'package:genui/genui.dart';
import 'dart:convert';

void main() {
  final rawJson = '''
[
  {
    "surfaceUpdate": {
      "surfaceId": "card-1",
      "components": [
        {
          "id": "root",
          "component": {
            "type": "Card",
            "padding": 16,
            "elevation": 2
          }
        },
        {
          "id": "title",
          "component": {
            "type": "Text",
            "content": "欢迎卡片",
            "style": "headline"
          }
        },
        {
          "id": "btn1",
          "component": {
            "type": "Button",
            "label": "点击我"
          }
        }
      ]
    }
  },
  {
    "beginRendering": {
      "surfaceId": "card-1"
    }
  }
]
''';

  final content = {
    'msgtype': 'm.text',
    'body': '[Interactive UI Element]',
    'format': 'org.matrix.custom.a2ui',
    'a2ui_content': jsonDecode(rawJson)
  };

  print('Testing A2uiEventParser...');
  try {
    final raw = content['a2ui_content'];
    final dynamic decoded;
    if (raw is String) {
      decoded = json.decode(raw);
    } else {
      decoded = raw;
    }

    if (decoded is List) {
      final messages = decoded
          .map((item) =>
              A2uiMessage.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      print('Parsed \${messages.length} messages successfully.');
    } else if (decoded is Map) {
      final messages = [A2uiMessage.fromJson(Map<String, dynamic>.from(decoded))];
      print('Parsed ' + messages.length.toString() + ' messages successfully.');
    }
  } catch (e, stack) {
    print('Error: ' + e.toString() + '\\n' + stack.toString());
  }
}
