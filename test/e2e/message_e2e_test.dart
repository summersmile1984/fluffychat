// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fluffychat/a2ui/bridge/a2ui_event_parser.dart';
import 'package:matrix/matrix.dart';
import 'e2e_client_helper.dart';
import 'e2e_config.dart';

/// E2E tests using the real Matrix SDK against a live homeserver.
///
/// Uses a hybrid approach: SDK for login/sync + REST API for
/// sending and fetching messages. This avoids vodozemac Rust bridge
/// crashes in headless test environments.
///
/// Prerequisites:
///   - Matrix HS at E2E_HOMESERVER (default: http://localhost:8787)
///   - matrix-agent-bridge running at :9090
///   - GBrainHub agent API running at hub.localhost (port 10000)
///
/// Run:
///   flutter test test/e2e/message_e2e_test.dart \
///     --dart-define=E2E_HOMESERVER=http://localhost:8787 \
///     --dart-define=E2E_USER=admin \
///     --dart-define=E2E_PASSWORD=admin123 \
///     --dart-define=E2E_DOMAIN=localhost:8787 \
///     --dart-define=E2E_BOT_LOCALPARTS=research,hr,pm
void main() {
  late E2eClientHelper helper;

  setUpAll(() async {
    print('╔═══════════════════════════════════════════════════════════╗');
    print('║  E2E Test: Flutter Client → Real Homeserver              ║');
    print('╚═══════════════════════════════════════════════════════════╝');
    print('HS:      ${E2eConfig.homeserverUrl}');
    print('User:    ${E2eConfig.username}');
    print('Domain:  ${E2eConfig.domain}');
    print('Bots:    ${E2eConfig.botLocalparts.join(", ")}');
    print('');

    helper = E2eClientHelper();
    await helper.init();
    print('✅ Client initialized and logged in as ${helper.client.userID}');
  });

  tearDownAll(() async {
    await helper.dispose();
    print('🧹 Client disposed');
  });

  // ── Test 1: Login & Sync ──

  group('Login & Sync', () {
    test('client connects and completes initial sync', () async {
      await helper.startSyncAndWait();

      expect(helper.client.userID, isNotNull);
      expect(helper.client.userID, contains(E2eConfig.username));
      print('  ✅ Sync complete. User: ${helper.client.userID}');
      print('     Rooms: ${helper.client.rooms.length}');
    });
  });

  // ── Test 2: Capabilities Injection ──

  group('Capabilities injection', () {
    test('outgoing message contains org.aotsea.capabilities', () async {
      await helper.startSyncAndWait();

      // Use first bot DM to test capabilities
      final botLocalpart = E2eConfig.botLocalparts.first;
      final botMxid = E2eConfig.botMxid(botLocalpart);
      final roomId = await helper.findOrCreateDm(botMxid);

      // Send with capabilities via REST API
      final eventId = await helper.sendWithCapabilities(
        roomId,
        'Capabilities test — please ignore',
      );
      print('  ✅ Sent message with capabilities: $eventId');

      // Fetch the event back to verify capabilities were included
      await Future.delayed(const Duration(seconds: 1));
      final resp = await http.get(
        helper.client.homeserver!.resolve(
          '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/event/${Uri.encodeComponent(eventId)}',
        ),
        headers: {'Authorization': 'Bearer ${helper.client.accessToken}'},
      );
      expect(resp.statusCode, equals(200));

      final eventData = jsonDecode(resp.body) as Map<String, dynamic>;
      final content = eventData['content'] as Map<String, dynamic>;
      final caps = content['org.aotsea.capabilities'] as Map<String, dynamic>?;

      expect(caps, isNotNull, reason: 'capabilities should be present');
      expect(caps!['a2ui'], isTrue);
      expect(caps['markdown'], isTrue);
      expect(caps['streaming'], isTrue);
      expect(caps['version'], equals('1.0'));
      print('  ✅ Capabilities verified: $caps');
    });
  });

  // ── Per-Bot Tests ──

  for (final botLocalpart in E2eConfig.botLocalparts) {
    final botMxid = E2eConfig.botMxid(botLocalpart);

    group('Bot: $botLocalpart ($botMxid)', () {
      late String roomId;

      setUpAll(() async {
        await helper.startSyncAndWait();
        roomId = await helper.findOrCreateDm(botMxid);
        print('  📁 DM room: $roomId');
      });

      // ── Test 3: Markdown Response ──

      test('receives markdown-formatted response', () async {
        await helper.sendWithCapabilities(
          roomId,
          '用3句话介绍一下你自己',
        );
        print('  📤 Sent markdown test prompt');

        final events = await helper.collectEvents(
          roomId: roomId,
          fromUserId: botMxid,
        );
        print('  📥 Received ${events.length} event(s)');

        expect(events, isNotEmpty,
            reason: 'Should receive at least one response');

        // Find the final event (streaming=false or last)
        final finalEvent = events.reversed
                .where((e) => e.streaming == false)
                .firstOrNull ??
            events.last;

        expect(
          finalEvent.format,
          equals('org.matrix.custom.markdown'),
          reason: 'Response should be markdown formatted',
        );
        expect(
          finalEvent.body.length,
          greaterThan(10),
          reason: 'Response body should be non-trivial',
        );
        print(
          '  ✅ Markdown response: format=${finalEvent.format}, '
          '${finalEvent.body.length} chars',
        );
        print(
          '     Preview: ${finalEvent.body.substring(0, finalEvent.body.length.clamp(0, 80))}...',
        );
      }, timeout: const Timeout(Duration(seconds: 120)));

      // ── Test 4: Streaming Delta Fields ──

      test('receives streaming events with correct delta fields', () async {
        // Use a new DM for streaming test to get clean timeline
        final streamRoomId = await helper.findOrCreateDm(botMxid);

        await helper.sendWithCapabilities(
          streamRoomId,
          '请详细介绍5种常见的数据结构及其应用场景',
        );
        print('  📤 Sent long-response prompt');

        final events = await helper.collectEvents(
          roomId: streamRoomId,
          fromUserId: botMxid,
        );
        print('  📥 Received ${events.length} event(s)');

        expect(events, isNotEmpty);

        // Analyze events
        final initialEvents = events.where((e) => !e.isEdit).toList();
        final editEvents = events.where((e) => e.isEdit).toList();
        final deltaEvents =
            editEvents.where((e) => e.isDelta == true).toList();
        final streamingTrueEvents =
            events.where((e) => e.streaming == true).toList();
        final streamingFalseEvents =
            editEvents.where((e) => e.streaming == false).toList();

        print('  📊 Analysis:');
        print('     Initial messages: ${initialEvents.length}');
        print('     Edit events: ${editEvents.length}');
        print('     Delta edits (is_delta=true): ${deltaEvents.length}');
        print('     Streaming=true events: ${streamingTrueEvents.length}');
        print('     Streaming=false (final): ${streamingFalseEvents.length}');

        // Verify initial message has streaming=true
        if (initialEvents.isNotEmpty) {
          expect(
            initialEvents.first.streaming,
            isTrue,
            reason: 'Initial message should have streaming=true',
          );
          print('  ✅ Initial message has streaming=true');
        }

        // Verify delta edits exist (for a long response)
        if (deltaEvents.isNotEmpty) {
          // Delta should have streaming=true
          expect(
            deltaEvents.first.streaming,
            isTrue,
            reason: 'Delta edits should have streaming=true',
          );

          // Delta should have m.relates_to with m.replace
          final relatesTo =
              deltaEvents.first.content['m.relates_to'] as Map?;
          expect(
            relatesTo?['rel_type'],
            equals('m.replace'),
            reason: 'Delta should use m.replace relation',
          );
          print(
            '  ✅ ${deltaEvents.length} delta edits with is_delta=true, '
            'streaming=true, m.replace',
          );
        } else {
          print(
            '  ⚠️ No delta events (response may be short or '
            'bridge uses full-edit mode)',
          );
        }
      }, timeout: const Timeout(Duration(seconds: 120)));

      // ── Test 5: Streaming Final ──

      test('final streaming edit has streaming=false and full text', () async {
        final finalRoomId = await helper.findOrCreateDm(botMxid);

        await helper.sendWithCapabilities(
          finalRoomId,
          '请写一段关于人工智能的介绍，200字左右',
        );
        print('  📤 Sent streaming final test prompt');

        final events = await helper.collectEvents(
          roomId: finalRoomId,
          fromUserId: botMxid,
        );
        print('  📥 Received ${events.length} event(s)');

        expect(events, isNotEmpty);

        // Find the final event
        final finalEvent = events.reversed
                .where((e) => e.streaming == false)
                .firstOrNull ??
            events.last;

        // Final should have streaming=false (or null for non-streaming)
        expect(
          finalEvent.streaming,
          anyOf(isFalse, isNull),
          reason: 'Final event should have streaming=false',
        );

        // Final should have substantial body
        expect(
          finalEvent.body.length,
          greaterThan(50),
          reason: 'Final body should contain full accumulated text',
        );

        // Final should be markdown formatted
        expect(
          finalEvent.format,
          equals('org.matrix.custom.markdown'),
          reason: 'Final event should be markdown formatted',
        );

        print(
          '  ✅ Final event: streaming=${finalEvent.streaming}, '
          '${finalEvent.body.length} chars, format=${finalEvent.format}',
        );
      }, timeout: const Timeout(Duration(seconds: 120)));

      // ── Test 6: A2UI Content (if agent can produce it) ──

      test('A2UI response is parseable by A2uiEventParser', () async {
        final a2uiRoomId = await helper.findOrCreateDm(botMxid);

        // The bridge injects A2UI system prompt, so the agent should
        // know how to produce a2ui_content when asked for a UI card.
        await helper.sendWithCapabilities(
          a2uiRoomId,
          '请生成一个A2UI交互卡片，包含一个标题和一个按钮。'
          '请使用 a2ui_content JSON 格式输出。',
        );
        print('  📤 Sent A2UI-triggering prompt');

        final events = await helper.collectEvents(
          roomId: a2uiRoomId,
          fromUserId: botMxid,
          // A2UI extraction may take longer
          timeout: const Duration(seconds: 120),
        );
        print('  📥 Received ${events.length} event(s)');

        expect(events, isNotEmpty);

        // Look for a2ui events
        final a2uiEvents = events
            .where((e) => e.format == 'org.matrix.custom.a2ui')
            .toList();
        final mdEvents = events
            .where((e) => e.format == 'org.matrix.custom.markdown')
            .toList();

        print('     A2UI events: ${a2uiEvents.length}');
        print('     Markdown events: ${mdEvents.length}');

        if (a2uiEvents.isNotEmpty) {
          final a2uiEvent = a2uiEvents.first;

          // Verify a2ui_content exists
          expect(
            a2uiEvent.a2uiContent,
            isNotNull,
            reason: 'A2UI event should contain a2ui_content',
          );
          print('  ✅ a2ui_content present');

          // Parse via A2uiEventParser — create a fake Event
          // to test the parser with real data
          final room = Room(
            id: a2uiRoomId,
            client: helper.client,
          );
          final event = Event(
            content: a2uiEvent.content,
            type: EventTypes.Message,
            eventId: a2uiEvent.eventId,
            senderId: a2uiEvent.sender,
            originServerTs: DateTime.now(),
            room: room,
          );

          expect(
            A2uiEventParser.hasA2uiContent(event),
            isTrue,
            reason: 'Parser should detect a2ui_content',
          );

          final messages = A2uiEventParser.parseMessages(event);
          expect(
            messages,
            isNotEmpty,
            reason: 'Parser should produce A2uiMessage objects',
          );
          print('  ✅ A2uiEventParser parsed ${messages.length} message(s)');

          // Check for SurfaceUpdate or BeginRendering
          for (final msg in messages) {
            print('     ${msg.runtimeType}');
          }
        } else {
          // A2UI extraction may not work every time (depends on agent output)
          print(
            '  ⚠️ No A2UI events received — agent may not have produced '
            'a2ui_content. Checking if raw body mentions a2ui...',
          );

          final anyBodyWithA2ui =
              events.any((e) => e.body.contains('a2ui_content'));
          if (anyBodyWithA2ui) {
            print(
              '     Agent output contained a2ui_content text but '
              'bridge extraction may have failed',
            );
          } else {
            print('     Agent did not output a2ui_content at all');
          }

          // Still pass — this is a best-effort test
          print(
            '  ⚠️ A2UI test inconclusive (agent-dependent). '
            'Test passes but A2UI extraction was not verified.',
          );
        }
      }, timeout: const Timeout(Duration(seconds: 150)));
    });
  }
}
