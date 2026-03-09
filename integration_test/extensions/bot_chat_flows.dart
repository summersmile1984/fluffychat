import 'package:fluffychat/a2ui/widgets/a2ui_message_bubble.dart';
import 'package:fluffychat/pages/chat/chat_view.dart';
import 'package:fluffychat/pages/chat/events/streaming_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';

import '../users.dart';
import 'wait_for.dart';

/// Extension methods for bot chat E2E flows.
///
/// Provides helpers to navigate to a bot's DM, send messages,
/// and wait for specific widget types to appear in responses.
extension BotChatFlows on WidgetTester {
  /// Navigate to a DM with the given bot.
  ///
  /// Assumes the app is on the ChatList screen.
  /// Searches for the bot by name, opens the chat, and waits for ChatView.
  Future<void> openBotDm(String botLocalpart) async {
    final tester = this;
    final mxid = botMxid(botLocalpart);

    // Search for the bot
    await tester.waitFor(find.byType(TextField));
    await tester.enterText(find.byType(TextField), mxid);
    await tester.pumpAndSettle();

    // Try to find and tap the bot in the list
    // May appear as display name or MXID
    final botFinder = find.text(mxid);

    try {
      await tester.waitFor(
        botFinder,
        timeout: const Duration(seconds: 10),
      );
      await tester.tap(botFinder.first);
      await tester.pumpAndSettle();
    } catch (_) {
      // Try searching by localpart only
      final localpartFinder = find.text(botLocalpart);
      if (localpartFinder.evaluate().isNotEmpty) {
        await tester.tap(localpartFinder.first);
        await tester.pumpAndSettle();
      }
    }

    // If we ended up on a "start chat" prompt, tap send
    if (find.byIcon(Icons.send_outlined).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.pumpAndSettle();
    }

    // Wait for the chat view
    await tester.waitFor(
      find.byType(ChatView),
      timeout: const Duration(seconds: 15),
    );
  }

  /// Send a text message in the current chat view.
  Future<void> sendChatMessage(String message) async {
    final tester = this;

    // Find the message input field
    final inputField = find.byType(TextField).last;
    await tester.enterText(inputField, message);
    await tester.pumpAndSettle();

    // Tap send button
    try {
      await tester.waitFor(
        find.byIcon(Icons.send_outlined),
        timeout: const Duration(seconds: 3),
      );
      await tester.tap(find.byIcon(Icons.send_outlined));
    } catch (_) {
      // Fallback: submit via keyboard
      await tester.testTextInput.receiveAction(TextInputAction.done);
    }
    await tester.pumpAndSettle();
  }

  /// Wait for a MarkdownBody widget to appear (indicating markdown rendering).
  Future<void> waitForMarkdownResponse({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    await waitFor(
      find.byType(MarkdownBody),
      timeout: timeout,
      skipPumpAndSettle: true,
    );
  }

  /// Wait for a StreamingMessageContent widget (streaming response).
  Future<void> waitForStreamingResponse({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    await waitFor(
      find.byType(StreamingMessageContent),
      timeout: timeout,
      skipPumpAndSettle: true,
    );
  }

  /// Wait for an A2uiMessageBubble widget (A2UI card response).
  Future<void> waitForA2uiResponse({
    Duration timeout = const Duration(seconds: 120),
  }) async {
    await waitFor(
      find.byType(A2uiMessageBubble),
      timeout: timeout,
      skipPumpAndSettle: true,
    );
  }

  /// Wait for a GenUiSurface widget inside an A2UI bubble.
  Future<void> waitForGenUiSurface({
    Duration timeout = const Duration(seconds: 120),
  }) async {
    await waitFor(
      find.byType(GenUiSurface),
      timeout: timeout,
      skipPumpAndSettle: true,
    );
  }

  /// Wait until StreamingMessageContent disappears (streaming finished).
  Future<void> waitForStreamingToFinish({
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final end = DateTime.now().add(timeout);

    // First wait for streaming to START
    try {
      await waitForStreamingResponse(
        timeout: const Duration(seconds: 60),
      );
    } catch (_) {
      // Streaming may have already finished
      return;
    }

    // Then wait for it to FINISH (StreamingMessageContent disappears
    // or blinking cursor stops)
    do {
      if (DateTime.now().isAfter(end)) break;
      await pump(const Duration(milliseconds: 500));
    } while (find.byType(StreamingMessageContent).evaluate().isNotEmpty);
  }
}
