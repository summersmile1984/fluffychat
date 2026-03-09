import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';

import 'package:fluffychat/a2ui/widgets/a2ui_message_bubble.dart';
import '../utils/fake_event_factory.dart';

/// Tests for [A2uiMessageBubble] rendering.
///
/// Verifies that A2UI events are correctly parsed and rendered
/// into GenUI surfaces, and that fallback text is shown when
/// parsing fails.
void main() {
  late FakeEventFactory factory;

  setUpAll(() async {
    factory = FakeEventFactory();
    await factory.init();
  });

  tearDownAll(() => factory.dispose());

  Widget buildA2uiBubble(event) {
    return MaterialApp(
      home: Scaffold(
        body: A2uiMessageBubble(
          event: event,
          textColor: Colors.black,
          linkColor: Colors.blue,
        ),
      ),
    );
  }

  group('A2uiMessageBubble', () {
    testWidgets('renders GenUiSurface for valid a2ui_content', (tester) async {
      final event = factory.makeA2uiEvent(
        '测试卡片 fallback',
        FakeEventFactory.sampleA2uiContent(),
      );
      await tester.pumpWidget(buildA2uiBubble(event));
      await tester.pump();

      // GenUiSurface should be rendered for the surface
      expect(find.byType(GenUiSurface), findsWidgets);
    });

    testWidgets('shows fallback body text when a2ui parsing fails',
        (tester) async {
      // Event with invalid a2ui_content (not parseable)
      final event = factory.makeA2uiEventFromJsonString(
        '解析失败时的 fallback 文本',
        'not valid json',
      );
      await tester.pumpWidget(buildA2uiBubble(event));
      await tester.pump();

      // Should show the fallback body text
      expect(find.text('解析失败时的 fallback 文本'), findsOneWidget);
      // Should NOT have GenUiSurface
      expect(find.byType(GenUiSurface), findsNothing);
    });

    testWidgets('shows body text above A2UI when body is not bracket-prefixed',
        (tester) async {
      final event = factory.makeA2uiEvent(
        '这是一个表单卡片',
        FakeEventFactory.sampleA2uiContent(),
      );
      await tester.pumpWidget(buildA2uiBubble(event));
      await tester.pump();

      // The body text should be visible (does not start with '[')
      expect(find.text('这是一个表单卡片'), findsOneWidget);
    });

    testWidgets(
        'hides body text when body starts with bracket (technical action)',
        (tester) async {
      final event = factory.makeA2uiEvent(
        '[submit_form]',
        FakeEventFactory.sampleA2uiContent(),
      );
      await tester.pumpWidget(buildA2uiBubble(event));
      await tester.pump();

      // Body starting with '[' is treated as technical and hidden
      expect(find.text('[submit_form]'), findsNothing);
    });

    testWidgets('renders multiple surfaces', (tester) async {
      // Create A2UI content with 2 different surfaces
      final event = factory.makeA2uiEvent(
        'Multi-surface test',
        [
          {
            'surfaceUpdate': {
              'surfaceId': 'surface-a',
              'components': [
                {
                  'id': 'root',
                  'component': {
                    'Text': {
                      'text': {'literalString': 'Surface A'},
                    },
                  },
                },
              ],
            },
          },
          {
            'beginRendering': {
              'surfaceId': 'surface-a',
              'root': 'root',
            },
          },
          {
            'surfaceUpdate': {
              'surfaceId': 'surface-b',
              'components': [
                {
                  'id': 'root',
                  'component': {
                    'Text': {
                      'text': {'literalString': 'Surface B'},
                    },
                  },
                },
              ],
            },
          },
          {
            'beginRendering': {
              'surfaceId': 'surface-b',
              'root': 'root',
            },
          },
        ],
      );
      await tester.pumpWidget(buildA2uiBubble(event));
      await tester.pump();

      // Should have 2 GenUiSurface widgets
      expect(find.byType(GenUiSurface), findsNWidgets(2));
    });
  });
}
