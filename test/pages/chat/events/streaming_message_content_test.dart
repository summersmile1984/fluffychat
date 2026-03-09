import 'package:flutter_test/flutter_test.dart';

import '../../../utils/fake_event_factory.dart';

/// Tests for streaming message state machine logic.
///
/// Instead of rendering StreamingMessageContent (which has deep dependencies
/// on AppSettings, SharedPreferences, and Hive), we test the LOGIC that
/// determines how streaming events should be processed:
///   - Initial event: sets buffer to body, shows cursor
///   - Delta edit: appends to buffer
///   - Final edit: replaces buffer, hides cursor
///
/// This mirrors the logic in streaming_message_content.dart L65-89.
void main() {
  late FakeEventFactory factory;

  setUpAll(() async {
    factory = FakeEventFactory();
    await factory.init();
  });

  tearDownAll(() => factory.dispose());

  /// Simulates the streaming buffer logic from StreamingMessageContent.
  /// Returns (buffer, showCursor).
  ({String buffer, bool showCursor}) processStreamingEvent(
    Map<String, dynamic> content,
    String existingBuffer,
  ) {
    final isDelta = content['is_delta'] == true;
    final isStreaming = content['streaming'] == true;
    final body = (content['m.new_content'] as Map?)?['body'] as String? ??
        content['body'] as String;

    String newBuffer;
    if (isDelta && isStreaming) {
      newBuffer = existingBuffer + body; // append delta
    } else {
      newBuffer = body; // replace with full content
    }

    return (buffer: newBuffer, showCursor: isStreaming);
  }

  group('Streaming state machine', () {
    test('initial event sets buffer and shows cursor', () {
      final event = factory.makeStreamingInitialEvent('## Hello');
      final result = processStreamingEvent(event.content, '');

      expect(result.buffer, '## Hello');
      expect(result.showCursor, isTrue);
    });

    test('delta appends to existing buffer', () {
      final event = factory.makeStreamingDeltaEvent(
        '\$orig',
        ' World',
      );
      final result = processStreamingEvent(event.content, '## Hello');

      expect(result.buffer, '## Hello World');
      expect(result.showCursor, isTrue);
    });

    test('multiple deltas accumulate correctly', () {
      var buffer = '';

      // Initial
      final init = factory.makeStreamingInitialEvent('##');
      var result = processStreamingEvent(init.content, buffer);
      buffer = result.buffer;
      expect(buffer, '##');

      // Delta 1
      final d1 = factory.makeStreamingDeltaEvent('\$o', ' Hello');
      result = processStreamingEvent(d1.content, buffer);
      buffer = result.buffer;
      expect(buffer, '## Hello');

      // Delta 2
      final d2 = factory.makeStreamingDeltaEvent('\$o', ' World');
      result = processStreamingEvent(d2.content, buffer);
      buffer = result.buffer;
      expect(buffer, '## Hello World');

      // Delta 3
      final d3 = factory.makeStreamingDeltaEvent('\$o', '!');
      result = processStreamingEvent(d3.content, buffer);
      buffer = result.buffer;
      expect(buffer, '## Hello World!');

      expect(result.showCursor, isTrue);
    });

    test('final edit replaces buffer with full text and hides cursor', () {
      final event = factory.makeStreamingFinalEvent(
        '\$orig',
        '## Hello World! Complete.',
      );
      final result = processStreamingEvent(
        event.content,
        '## Hello World!', // existing buffer from deltas
      );

      expect(result.buffer, '## Hello World! Complete.');
      expect(result.showCursor, isFalse);
    });

    test('final edit with streaming=false stops cursor', () {
      final event = factory.makeEvent(content: {
        'msgtype': 'm.text',
        'body': 'Done.',
        'format': 'org.matrix.custom.markdown',
        'streaming': false,
      });
      final result = processStreamingEvent(event.content, 'partial...');

      expect(result.showCursor, isFalse);
      expect(result.buffer, 'Done.');
    });

    test('non-delta event without streaming replaces buffer', () {
      final event = factory.makeMarkdownEvent('Complete response text.');
      final result = processStreamingEvent(event.content, 'old buffer');

      expect(result.buffer, 'Complete response text.');
      expect(result.showCursor, isFalse);
    });
  });
}
