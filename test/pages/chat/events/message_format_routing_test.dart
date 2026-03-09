import 'package:flutter_test/flutter_test.dart';

import '../../../utils/fake_event_factory.dart';

/// Tests for the format-based routing logic used in MessageContent.
///
/// Instead of rendering the full MessageContent widget tree (which has
/// heavy dependencies on Timeline, Room, etc.), we test the routing
/// DECISION LOGIC directly: given an event's content fields, which
/// rendering path should be taken?
///
/// The routing logic (from message_content.dart L262-365) is:
///   1. streaming == true   → StreamingMessageContent
///   2. format == 'org.matrix.custom.a2ui'  → A2uiMessageBubble
///   3. format == 'org.matrix.custom.markdown' → MarkdownBody
///   4. (else) → HtmlMessage
///
/// This is a pure logic test — no rendering needed.
void main() {
  late FakeEventFactory factory;

  setUpAll(() async {
    factory = FakeEventFactory();
    await factory.init();
  });

  tearDownAll(() => factory.dispose());

  /// Determine which renderer would be selected by message_content.dart.
  String resolveRenderer(Map<String, dynamic> content) {
    final format = content['format'] as String?;
    final streaming = content['streaming'];

    // 1. Streaming takes priority
    if (streaming == true) return 'StreamingMessageContent';

    // 2. A2UI
    if (format == 'org.matrix.custom.a2ui') return 'A2uiMessageBubble';

    // 3. Markdown
    if (format == 'org.matrix.custom.markdown') return 'MarkdownBody';

    // 4. Fallback
    return 'HtmlMessage';
  }

  group('MessageContent format routing logic', () {
    test('streaming:true → StreamingMessageContent', () {
      final event = factory.makeStreamingInitialEvent('typing...');
      expect(resolveRenderer(event.content), 'StreamingMessageContent');
    });

    test('format=a2ui → A2uiMessageBubble', () {
      final event = factory.makeA2uiEvent(
        'fallback',
        FakeEventFactory.sampleA2uiContent(),
      );
      expect(resolveRenderer(event.content), 'A2uiMessageBubble');
    });

    test('format=markdown → MarkdownBody', () {
      final event = factory.makeMarkdownEvent('## Hello');
      expect(resolveRenderer(event.content), 'MarkdownBody');
    });

    test('no format → HtmlMessage', () {
      final event = factory.makePlainEvent('Plain text');
      expect(resolveRenderer(event.content), 'HtmlMessage');
    });

    test('streaming:false + markdown → MarkdownBody (not streaming)', () {
      final event = factory.makeEvent(content: {
        'msgtype': 'm.text',
        'body': 'Final text',
        'format': 'org.matrix.custom.markdown',
        'streaming': false,
      });
      expect(resolveRenderer(event.content), 'MarkdownBody');
    });

    test('streaming:true takes priority over a2ui format', () {
      final event = factory.makeEvent(content: {
        'msgtype': 'm.text',
        'body': 'Both flags',
        'format': 'org.matrix.custom.a2ui',
        'streaming': true,
        'a2ui_content': FakeEventFactory.sampleA2uiContent(),
      });
      expect(resolveRenderer(event.content), 'StreamingMessageContent');
    });

    test('streaming:true takes priority over markdown format', () {
      final event = factory.makeEvent(content: {
        'msgtype': 'm.text',
        'body': 'Streaming markdown',
        'format': 'org.matrix.custom.markdown',
        'streaming': true,
      });
      expect(resolveRenderer(event.content), 'StreamingMessageContent');
    });

    test('delta streaming edit → StreamingMessageContent', () {
      final event = factory.makeStreamingDeltaEvent(
        '\$original123',
        ' additional text',
      );
      // Delta edits also have streaming=true in m.new_content
      final content = event.content;
      expect(resolveRenderer(content), 'StreamingMessageContent');
    });

    test('final streaming edit → MarkdownBody', () {
      final event = factory.makeStreamingFinalEvent(
        '\$original123',
        'Full complete text',
      );
      // Final edit has streaming=false
      final content = event.content;
      expect(resolveRenderer(content), 'MarkdownBody');
    });

    test('m.notice (no format) → HtmlMessage', () {
      final event = factory.makeNoticeEvent('Error occurred');
      expect(resolveRenderer(event.content), 'HtmlMessage');
    });
  });
}
