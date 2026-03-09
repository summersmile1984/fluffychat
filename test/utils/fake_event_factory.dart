// ignore_for_file: depend_on_referenced_packages

import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Factory for creating fake [Event] objects in tests.
///
/// Provides helper methods to construct events with specific content
/// structures (markdown, streaming, A2UI, etc.) without needing a real
/// Matrix homeserver connection.
class FakeEventFactory {
  static int _instanceCount = 0;
  late Client client;
  late Room room;
  int _eventCounter = 0;

  /// Initialize with a fake Matrix client and room.
  /// Must be called (and awaited) before using any factory methods.
  Future<void> init() async {
    final dbName = 'test_factory_${_instanceCount++}';
    client = Client(
      'FluffyChat Test $dbName',
      httpClient: FakeMatrixApi()
        ..api['GET']!['/.well-known/matrix/client'] = (req) => {},
      database: await MatrixSdkDatabase.init(
        dbName,
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    await client.checkHomeserver(
      Uri.parse('https://fakeserver.notexisting'),
    );
    // Create a fake room in the client's internal state
    room = Room(id: '!testroom:example.com', client: client);
  }

  String _nextEventId() => '\$evt_${_eventCounter++}';

  // ── Core builder ──

  /// Create an Event with arbitrary content.
  Event makeEvent({
    required Map<String, dynamic> content,
    String type = EventTypes.Message,
    String? eventId,
    String senderId = '@bot:example.com',
  }) {
    return Event(
      content: content,
      type: type,
      eventId: eventId ?? _nextEventId(),
      senderId: senderId,
      originServerTs: DateTime.now(),
      room: room,
    );
  }

  // ── Convenience builders ──

  /// Plain m.text message without any format field.
  Event makePlainEvent(String body) => makeEvent(
        content: {'msgtype': 'm.text', 'body': body},
      );

  /// m.notice message (bridge error notices, etc.)
  Event makeNoticeEvent(String body) => makeEvent(
        content: {'msgtype': 'm.notice', 'body': body},
      );

  /// Markdown-formatted message.
  Event makeMarkdownEvent(String body) => makeEvent(
        content: {
          'msgtype': 'm.text',
          'body': body,
          'format': 'org.matrix.custom.markdown',
        },
      );

  /// Initial streaming message (streaming=true, no delta).
  Event makeStreamingInitialEvent(String body) => makeEvent(
        content: {
          'msgtype': 'm.text',
          'body': body,
          'format': 'org.matrix.custom.markdown',
          'streaming': true,
        },
      );

  /// Delta streaming edit event.
  Event makeStreamingDeltaEvent(
    String originalEventId,
    String deltaBody,
  ) =>
      makeEvent(
        content: {
          'msgtype': 'm.text',
          'body': '* $deltaBody',
          'format': 'org.matrix.custom.markdown',
          'streaming': true,
          'is_delta': true,
          'm.new_content': {
            'msgtype': 'm.text',
            'body': deltaBody,
            'format': 'org.matrix.custom.markdown',
            'streaming': true,
            'is_delta': true,
          },
          'm.relates_to': {
            'rel_type': 'm.replace',
            'event_id': originalEventId,
          },
        },
      );

  /// Final streaming edit event (streaming=false, full text).
  Event makeStreamingFinalEvent(
    String originalEventId,
    String fullBody,
  ) =>
      makeEvent(
        content: {
          'msgtype': 'm.text',
          'body': '* $fullBody',
          'format': 'org.matrix.custom.markdown',
          'streaming': false,
          'm.new_content': {
            'msgtype': 'm.text',
            'body': fullBody,
            'format': 'org.matrix.custom.markdown',
            'streaming': false,
          },
          'm.relates_to': {
            'rel_type': 'm.replace',
            'event_id': originalEventId,
          },
        },
      );

  /// A2UI card message.
  Event makeA2uiEvent(
    String fallbackBody,
    List<Map<String, dynamic>> a2uiContent,
  ) =>
      makeEvent(
        content: {
          'msgtype': 'm.text',
          'body': fallbackBody,
          'format': 'org.matrix.custom.a2ui',
          'a2ui_content': a2uiContent,
        },
      );

  /// A2UI event with a2ui_content as a JSON string (test alternate parsing).
  Event makeA2uiEventFromJsonString(
    String fallbackBody,
    String a2uiJsonString,
  ) =>
      makeEvent(
        content: {
          'msgtype': 'm.text',
          'body': fallbackBody,
          'format': 'org.matrix.custom.a2ui',
          'a2ui_content': a2uiJsonString,
        },
      );

  // ── Sample A2UI payloads ──

  /// Standard SurfaceUpdate + BeginRendering test payload.
  ///
  /// Uses GenUI's internal format:
  ///   - Wrapper keys: `{surfaceUpdate: {...}}` not `{type: "SurfaceUpdate"}`
  ///   - `components` as `List<{id, component: {TypeName: {...props}}}>`
  ///   - `beginRendering` requires `surfaceId` and `root`
  static List<Map<String, dynamic>> sampleA2uiContent({
    String surfaceId = 'test-surface',
  }) =>
      [
        {
          'surfaceUpdate': {
            'surfaceId': surfaceId,
            'components': [
              {
                'id': 'root',
                'component': {
                  'Card': {'child': 'col'},
                },
              },
              {
                'id': 'col',
                'component': {
                  'Column': {
                    'children': ['title', 'btn'],
                  },
                },
              },
              {
                'id': 'title',
                'component': {
                  'Text': {
                    'text': {'literalString': '测试表单'},
                  },
                },
              },
              {
                'id': 'btn',
                'component': {
                  'Button': {
                    'child': 'btnTxt',
                    'action': {'name': 'submit'},
                  },
                },
              },
              {
                'id': 'btnTxt',
                'component': {
                  'Text': {
                    'text': {'literalString': '提交'},
                  },
                },
              },
            ],
          },
        },
        {
          'beginRendering': {
            'surfaceId': surfaceId,
            'root': 'root',
          },
        },
      ];

  /// Dispose the client to free resources.
  Future<void> dispose() async {
    await client.dispose();
  }
}
