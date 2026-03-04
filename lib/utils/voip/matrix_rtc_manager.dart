import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// Manages MatrixRTC signaling and LiveKit JWT token acquisition.
class MatrixRTCManager {
  final Client client;

  MatrixRTCManager({required this.client});

  /// The LiveKit WebSocket URL returned by the last successful token request.
  /// Used by the caller to connect to the LiveKit server.
  String? lastLivekitUrl;

  /// Request a LiveKit JWT token from the homeserver's /livekit/get_token endpoint.
  ///
  /// Returns the JWT string and sets [lastLivekitUrl] to the LiveKit WS URL.
  /// The [roomId] should be the Matrix room ID (e.g. "!abc:server.name").
  Future<String> getLivekitJwt(String roomId) async {
    final homeserver = client.homeserver;
    if (homeserver == null) {
      throw Exception('Client has no homeserver configured');
    }

    // Obtain a Matrix OpenID token for authentication
    final userId = client.userID;
    if (userId == null) {
      throw Exception('Client has no logged-in user');
    }
    final openIdToken = await client.requestOpenIdToken(userId, {});

    // Build the token endpoint URL from the homeserver
    final tokenUrl = homeserver.replace(
      scheme: homeserver.scheme == 'wss' ? 'https' : (homeserver.scheme == 'ws' ? 'http' : homeserver.scheme),
      path: '/livekit/get_token',
    );

    Logs().i('[MatrixRTC] Requesting LiveKit JWT from $tokenUrl for room $roomId');

    try {
      final response = await http.post(
        tokenUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'room_id': roomId,
          'openid_token': openIdToken.toJson(),
          'device_id': client.deviceID,
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final jwt = json['jwt'] as String;
        lastLivekitUrl = json['url'] as String;
        Logs().i('[MatrixRTC] Got LiveKit JWT, WS URL: $lastLivekitUrl');
        return jwt;
      } else {
        throw Exception(
          'Failed to get LiveKit JWT: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      Logs().e('[MatrixRTC] Error requesting LiveKit JWT', e);
      rethrow;
    }
  }
}
