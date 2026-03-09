import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';

import 'package:fluffychat/a2ui/bridge/a2ui_event_parser.dart';
import '../utils/fake_event_factory.dart';

void main() {
  late FakeEventFactory factory;

  setUpAll(() async {
    factory = FakeEventFactory();
    await factory.init();
  });

  tearDownAll(() => factory.dispose());

  group('A2uiEventParser', () {
    group('hasA2uiContent', () {
      test('returns true when a2ui_content is present', () {
        final event = factory.makeA2uiEvent(
          'fallback text',
          FakeEventFactory.sampleA2uiContent(),
        );
        expect(A2uiEventParser.hasA2uiContent(event), isTrue);
      });

      test('returns false for plain text message', () {
        final event = factory.makePlainEvent('hello');
        expect(A2uiEventParser.hasA2uiContent(event), isFalse);
      });

      test('returns false for markdown message', () {
        final event = factory.makeMarkdownEvent('# Title');
        expect(A2uiEventParser.hasA2uiContent(event), isFalse);
      });

      test('returns false for streaming message', () {
        final event = factory.makeStreamingInitialEvent('chunk');
        expect(A2uiEventParser.hasA2uiContent(event), isFalse);
      });
    });

    group('parseMessages', () {
      test('parses List<Map> a2ui_content correctly', () {
        final event = factory.makeA2uiEvent(
          'fallback',
          FakeEventFactory.sampleA2uiContent(),
        );
        final messages = A2uiEventParser.parseMessages(event);

        expect(messages, hasLength(2));
        expect(messages[0], isA<SurfaceUpdate>());
        expect(messages[1], isA<BeginRendering>());
      });

      test('parses single Map a2ui_content', () {
        final event = factory.makeEvent(content: {
          'msgtype': 'm.text',
          'body': 'fallback',
          'format': 'org.matrix.custom.a2ui',
          'a2ui_content': {
            'surfaceUpdate': {
              'surfaceId': 'single',
              'components': [
                {
                  'id': 'root',
                  'component': {
                    'Text': {
                      'text': {'literalString': 'hello'},
                    },
                  },
                },
              ],
            },
          },
        });
        final messages = A2uiEventParser.parseMessages(event);

        expect(messages, hasLength(1));
        expect(messages[0], isA<SurfaceUpdate>());
      });

      test('parses JSON string a2ui_content', () {
        final a2uiJson = json.encode(FakeEventFactory.sampleA2uiContent());
        final event = factory.makeA2uiEventFromJsonString(
          'fallback',
          a2uiJson,
        );
        final messages = A2uiEventParser.parseMessages(event);

        expect(messages, hasLength(2));
        expect(messages[0], isA<SurfaceUpdate>());
        expect(messages[1], isA<BeginRendering>());
      });

      test('returns empty list for null a2ui_content', () {
        final event = factory.makePlainEvent('no a2ui');
        final messages = A2uiEventParser.parseMessages(event);
        expect(messages, isEmpty);
      });

      test('returns empty list for invalid JSON string', () {
        final event = factory.makeA2uiEventFromJsonString(
          'fallback',
          'not valid json at all',
        );
        final messages = A2uiEventParser.parseMessages(event);
        expect(messages, isEmpty);
      });

      test('returns empty list for non-array non-map decoded value', () {
        final event = factory.makeA2uiEventFromJsonString(
          'fallback',
          '"just a string"',
        );
        final messages = A2uiEventParser.parseMessages(event);
        expect(messages, isEmpty);
      });

      test('extracts correct surfaceId from SurfaceUpdate', () {
        final event = factory.makeA2uiEvent(
          'fallback',
          FakeEventFactory.sampleA2uiContent(surfaceId: 'my-form'),
        );
        final messages = A2uiEventParser.parseMessages(event);

        final surfaceUpdate = messages[0] as SurfaceUpdate;
        expect(surfaceUpdate.surfaceId, equals('my-form'));
      });
    });
  });
}
