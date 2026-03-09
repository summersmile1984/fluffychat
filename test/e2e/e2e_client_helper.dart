// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'e2e_config.dart';

/// Helper class for E2E tests that manages a real Matrix client connection.
///
/// Uses a hybrid approach:
/// - SDK Client for login and initial sync (room listing)
/// - Direct REST API calls for sending messages and fetching responses
///
/// This avoids the vodozemac Rust bridge dependency that crashes
/// the sync loop in headless `flutter test` environments.
class E2eClientHelper {
  late Client client;
  late String _accessToken;
  late Uri _homeserver;
  bool _synced = false;

  /// Initialize the client and login to the homeserver.
  Future<void> init() async {
    client = Client(
      'FluffyChat E2E Test',
      database: await MatrixSdkDatabase.init(
        'e2e_test_${DateTime.now().millisecondsSinceEpoch}',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
      defaultNetworkRequestTimeout: const Duration(seconds: 120),
    );

    await client.checkHomeserver(Uri.parse(E2eConfig.homeserverUrl));

    await client.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: E2eConfig.username),
      password: E2eConfig.password,
    );

    // Cache access token and homeserver for direct API calls
    _accessToken = client.accessToken!;
    _homeserver = client.homeserver!;

    // Stop the background sync loop to prevent vodozemac crash-loops
    client.backgroundSync = false;
  }

  /// Wait until initial sync completes.
  Future<void> startSyncAndWait({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_synced) return;

    if (client.prevBatch != null) {
      _synced = true;
      return;
    }

    await client.onSyncStatus.stream
        .firstWhere((s) => s.status == SyncStatus.finished)
        .timeout(timeout);
    _synced = true;
  }

  /// Make an authenticated HTTP request to the homeserver.
  Future<http.Response> _apiGet(String path, [Map<String, String>? query]) async {
    final uri = _homeserver.resolve(path).replace(queryParameters: query);
    return http.get(uri, headers: {'Authorization': 'Bearer $_accessToken'});
  }

  Future<http.Response> _apiPut(String path, Map<String, dynamic> body) async {
    final uri = _homeserver.resolve(path);
    return http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }

  /// Find or create a DM room with the given bot user ID.
  ///
  /// Uses the REST API to search for existing rooms where both
  /// the user and bot are joined members, since the SDK's in-memory
  /// room list doesn't have DM data (background sync is disabled).
  Future<String> findOrCreateDm(String botMxid) async {
    // First, try to find existing room via REST API
    final existingRoomId = await _findExistingRoomWithBot(botMxid);
    if (existingRoomId != null) return existingRoomId;

    // Create new DM
    final roomId = await client.createRoom(
      isDirect: true,
      invite: [botMxid],
      preset: CreateRoomPreset.trustedPrivateChat,
    );

    // Wait for bot to auto-join (appservice needs time to process invite)
    await _waitForBotJoin(roomId, botMxid);
    return roomId;
  }

  /// Search joined rooms for one where [botMxid] is also a joined member.
  Future<String?> _findExistingRoomWithBot(String botMxid) async {
    // Get joined rooms
    final resp = await _apiGet('/_matrix/client/v3/joined_rooms');
    if (resp.statusCode != 200) return null;

    final rooms = (jsonDecode(resp.body)['joined_rooms'] as List).cast<String>();

    // Check each room for the bot (most recent rooms first — reverse order)
    for (final roomId in rooms.reversed) {
      final encodedRoom = Uri.encodeComponent(roomId);
      final memberResp = await _apiGet(
        '/_matrix/client/v3/rooms/$encodedRoom/members',
        {'membership': 'join'},
      );
      if (memberResp.statusCode != 200) continue;

      final members = (jsonDecode(memberResp.body)['chunk'] as List)
          .map((m) => m['state_key'] as String)
          .toList();

      // Found a room where both user and bot are joined
      if (members.contains(botMxid) && members.length <= 3) {
        return roomId;
      }
    }
    return null;
  }

  /// Wait for bot to join a room by polling membership via REST API.
  Future<void> _waitForBotJoin(String roomId, String botMxid, {
    Duration timeout = const Duration(seconds: 15),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final encodedRoom = Uri.encodeComponent(roomId);
      final resp = await _apiGet(
        '/_matrix/client/v3/rooms/$encodedRoom/members',
        {'membership': 'join'},
      );
      if (resp.statusCode == 200) {
        final members = (jsonDecode(resp.body)['chunk'] as List)
            .map((m) => m['state_key'] as String)
            .toList();
        if (members.contains(botMxid)) return;
      }
      await Future.delayed(pollInterval);
    }
    print('  ⚠️ Bot $botMxid did not join room $roomId within timeout');
  }

  /// Send a text message with Turning Agent capabilities.
  /// Uses the REST API directly instead of the SDK to avoid
  /// requiring room objects from sync.
  Future<String> sendWithCapabilities(
    String roomId,
    String message,
  ) async {
    final txnId = 'e2e_${DateTime.now().millisecondsSinceEpoch}';
    final resp = await _apiPut(
      '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/$txnId',
      {
        'msgtype': 'm.text',
        'body': message,
        'org.aotsea.capabilities': {
          'a2ui': true,
          'markdown': true,
          'streaming': true,
          'version': '1.0',
        },
      },
    );

    if (resp.statusCode != 200) {
      throw Exception('Failed to send message: ${resp.statusCode} ${resp.body}');
    }

    final eventId = jsonDecode(resp.body)['event_id'] as String;
    return eventId;
  }

  /// Fetch recent messages from a room via the REST API.
  /// Returns events most-recent-first.
  Future<List<Map<String, dynamic>>> _fetchMessages(
    String roomId, {
    int limit = 50,
    String? from,
    String dir = 'b', // backward from most recent
  }) async {
    final query = <String, String>{
      'limit': limit.toString(),
      'dir': dir,
      if (from != null) 'from': from,
    };
    final resp = await _apiGet(
      '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/messages',
      query,
    );

    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch messages: ${resp.statusCode} ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final chunk = (data['chunk'] as List).cast<Map<String, dynamic>>();
    return chunk;
  }

  /// Collect all m.room.message events from a specific sender in a room.
  ///
  /// Uses a polling approach via the REST /messages API.
  /// Returns after [settleDelay] with no new events, or on [timeout].
  Future<List<CollectedEvent>> collectEvents({
    required String roomId,
    required String fromUserId,
    Duration timeout = const Duration(milliseconds: 90000),
    Duration settleDelay = const Duration(milliseconds: 8000),
    Duration pollInterval = const Duration(milliseconds: 3000),
  }) async {
    final events = <CollectedEvent>[];
    final seenIds = <String>{};
    final end = DateTime.now().add(timeout);
    DateTime lastNewEvent = DateTime.now();

    while (DateTime.now().isBefore(end)) {
      try {
        final messages = await _fetchMessages(roomId, limit: 50);

        for (final msg in messages) {
          final eventId = msg['event_id'] as String?;
          if (eventId == null || seenIds.contains(eventId)) continue;
          if (msg['type'] != 'm.room.message') continue;
          if (msg['sender'] != fromUserId) continue;

          seenIds.add(eventId);

          final content = msg['content'] as Map<String, dynamic>? ?? {};

          // Skip m.notice (error messages from bridge)
          if (content['msgtype'] == 'm.notice') continue;

          final isEdit =
              (content['m.relates_to'] as Map?)?.containsKey('rel_type') ??
                  false;
          final effectiveContent = isEdit
              ? (content['m.new_content'] as Map<String, dynamic>? ?? content)
              : content;

          events.add(CollectedEvent(
            eventId: eventId,
            sender: msg['sender'] as String,
            body: effectiveContent['body'] as String? ?? '',
            content: content,
            isEdit: isEdit,
            streaming: effectiveContent['streaming'] as bool?,
            isDelta: effectiveContent['is_delta'] as bool?,
            a2uiContent: effectiveContent['a2ui_content'],
            format: effectiveContent['format'] as String?,
          ));

          lastNewEvent = DateTime.now();
        }
      } catch (e) {
        print('  ⚠️ Poll error: $e');
      }

      // Check settle: if enough time passed since last new event, we're done
      if (events.isNotEmpty &&
          DateTime.now().difference(lastNewEvent) > settleDelay) {
        break;
      }

      await Future.delayed(pollInterval);
    }

    return events;
  }

  /// Dispose the client and free resources.
  Future<void> dispose() async {
    client.backgroundSync = false;
    await client.dispose();
  }
}

/// A collected Matrix event with parsed fields.
class CollectedEvent {
  final String eventId;
  final String sender;
  final String body;
  final Map<String, dynamic> content;
  final bool isEdit;
  final bool? streaming;
  final bool? isDelta;
  final dynamic a2uiContent;
  final String? format;

  const CollectedEvent({
    required this.eventId,
    required this.sender,
    required this.body,
    required this.content,
    required this.isEdit,
    this.streaming,
    this.isDelta,
    this.a2uiContent,
    this.format,
  });

  @override
  String toString() =>
      'CollectedEvent(id=$eventId, edit=$isEdit, streaming=$streaming, '
      'delta=$isDelta, format=$format, body=${body.length > 50 ? '${body.substring(0, 50)}...' : body})';
}
