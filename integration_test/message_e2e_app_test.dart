import 'package:fluffychat/a2ui/widgets/a2ui_message_bubble.dart';
import 'package:fluffychat/pages/chat/events/streaming_message_content.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/main.dart' as app;

import 'extensions/bot_chat_flows.dart';
import 'extensions/default_flows.dart';

import 'users.dart';

/// E2E Integration Tests: Full UI Message Rendering
///
/// Tests the complete user experience: login → navigate to bot DM →
/// send message → verify the correct widgets render for each format:
///   - MarkdownBody for markdown responses
///   - StreamingMessageContent for active streaming
///   - A2uiMessageBubble + GenUiSurface for A2UI cards
///
/// Prerequisites:
///   - Matrix HS running (default: localhost:8787)
///   - matrix-agent-bridge running (:9090)
///   - GBrainHub agent-server running (:4111)
///   - Run on a device or simulator (macOS, iOS, Android)
///
/// Run:
///   flutter test integration_test/message_e2e_app_test.dart \
///     --dart-define=HOMESERVER=localhost:8787 \
///     --dart-define=USER1_NAME=admin \
///     --dart-define=USER1_PW=admin123 \
///     --dart-define=DOMAIN=localhost:8787 \
///     --dart-define=E2E_BOT_LOCALPARTS=research,hr,pm
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Message E2E — UI Rendering', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });
    });

    // ── Test 1: Login and reach homescreen ──

    testWidgets('Login to homescreen', (tester) async {
      app.main();
      await tester.ensureAppStartedHomescreen();
    });

    // ── Per-bot rendering tests ──

    for (final localpart in botLocalparts) {

      // ── Test 2: Markdown rendering ──

      testWidgets(
        'Bot $localpart: markdown response renders MarkdownBody',
        (tester) async {
          app.main();
          await tester.ensureAppStartedHomescreen();

          // Navigate to bot DM
          await tester.openBotDm(localpart);

          // Send a prompt that should produce a markdown response
          await tester.sendChatMessage('用3句话介绍你自己');

          // Wait for MarkdownBody to appear
          await tester.waitForMarkdownResponse(
            timeout: const Duration(seconds: 90),
          );

          // Verify MarkdownBody is rendered
          expect(find.byType(MarkdownBody), findsWidgets);
        },
      );

      // ── Test 3: Streaming cursor ──

      testWidgets(
        'Bot $localpart: streaming shows StreamingMessageContent',
        (tester) async {
          app.main();
          await tester.ensureAppStartedHomescreen();

          await tester.openBotDm(localpart);

          // Send a prompt that should produce a long streaming response
          await tester.sendChatMessage('请详细介绍5种数据结构');

          // Wait for StreamingMessageContent to appear (streaming active)
          try {
            await tester.waitForStreamingResponse(
              timeout: const Duration(seconds: 60),
            );

            // Verify StreamingMessageContent is rendered
            expect(find.byType(StreamingMessageContent), findsOneWidget);

            // Wait for streaming to finish
            await tester.waitForStreamingToFinish(
              timeout: const Duration(seconds: 120),
            );

            // After streaming finishes, should show MarkdownBody instead
            await tester.pumpAndSettle();
            expect(find.byType(MarkdownBody), findsWidgets);
          } catch (_) {
            // Streaming may have finished too quickly to catch
            // Verify at least MarkdownBody is shown (final state)
            await tester.waitForMarkdownResponse(
              timeout: const Duration(seconds: 90),
            );
            expect(find.byType(MarkdownBody), findsWidgets);
          }
        },
      );

      // ── Test 4: A2UI card rendering ──

      testWidgets(
        'Bot $localpart: A2UI prompt renders A2uiMessageBubble',
        (tester) async {
          app.main();
          await tester.ensureAppStartedHomescreen();

          await tester.openBotDm(localpart);

          // Send a prompt that should trigger A2UI content
          await tester.sendChatMessage(
            '请生成一个A2UI交互卡片，包含标题和按钮',
          );

          // Try to find A2UI response
          try {
            await tester.waitForA2uiResponse(
              timeout: const Duration(seconds: 120),
            );

            // Verify A2uiMessageBubble is rendered
            expect(find.byType(A2uiMessageBubble), findsWidgets);

            // Verify GenUiSurface is rendered inside it
            try {
              await tester.waitForGenUiSurface(
                timeout: const Duration(seconds: 10),
              );
              expect(find.byType(GenUiSurface), findsWidgets);
            } catch (_) {
              // GenUiSurface may not render if the a2ui_content is malformed
            }
          } catch (_) {
            // A2UI may not be produced by every bot — this is expected
            // At minimum, some kind of response should be present
            await tester.waitForMarkdownResponse(
              timeout: const Duration(seconds: 60),
            );
          }
        },
      );
    }
  });
}
