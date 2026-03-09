import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

import 'matrix_rtc_manager.dart';

/// The current state of a LiveKit call.
enum LiveKitCallState {
  /// No active call.
  idle,

  /// Requesting JWT token and connecting to LiveKit.
  connecting,

  /// Connected to LiveKit room, media flowing.
  connected,

  /// Call is ending / disconnecting.
  ending,

  /// Call ended normally or with an error.
  ended,
}

/// Manages a single LiveKit-based 1:1 call.
///
/// Handles:
/// - JWT token acquisition via [MatrixRTCManager]
/// - LiveKit Room connection and media track management
/// - State and track change notifications for the UI
class LiveKitPlugin {
  final Client client;
  final VoIP? voip;
  late final MatrixRTCManager _rtcManager;

  lk.Room? _livekitRoom;
  lk.EventsListener<lk.RoomEvent>? _listener;

  /// SDK GroupCallSession for MatrixRTC signaling.
  GroupCallSession? _groupCallSession;

  /// The current call state.
  LiveKitCallState _callState = LiveKitCallState.idle;
  LiveKitCallState get callState => _callState;

  /// The Matrix room ID of the current call.
  String? _currentRoomId;
  String? get currentRoomId => _currentRoomId;

  /// Whether the call includes video.
  bool _isVideoCall = false;
  bool get isVideoCall => _isVideoCall;

  /// Whether the local microphone is muted.
  bool _isMicMuted = false;
  bool get isMicMuted => _isMicMuted;

  /// Whether the local camera is disabled.
  bool _isCamDisabled = false;
  bool get isCamDisabled => _isCamDisabled;

  /// Stream of state changes for the UI to listen to.
  final StreamController<LiveKitCallState> onCallStateChanged =
      StreamController<LiveKitCallState>.broadcast();

  /// Stream of track updates (subscribe/unsubscribe/publish/unpublish).
  final StreamController<void> onTracksChanged =
      StreamController<void>.broadcast();

  /// Error message if the call failed.
  String? lastError;

  LiveKitPlugin({required this.client, this.voip}) {
    _rtcManager = MatrixRTCManager(client: client);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Start a 1:1 call in the given Matrix [roomId].
  /// Set [isVideo] to true for a video call, false for audio-only.
  Future<void> startCall(String roomId, {bool isVideo = true}) async {
    if (_callState != LiveKitCallState.idle &&
        _callState != LiveKitCallState.ended) {
      Logs().w('[LiveKit] Cannot start call — already in state $_callState');
      return;
    }

    _currentRoomId = roomId;
    _isVideoCall = isVideo;
    _isMicMuted = false;
    _isCamDisabled = false;
    lastError = null;
    _setCallState(LiveKitCallState.connecting);

    try {
      // 1. Get a LiveKit JWT token from the homeserver
      Logs().i('[LiveKit] Requesting JWT for room $roomId...');
      final jwt = await _rtcManager.getLivekitJwt(roomId);
      final wsUrl = _rtcManager.lastLivekitUrl;

      if (wsUrl == null || wsUrl.isEmpty) {
        throw Exception('LiveKit WS URL not returned by server');
      }

      // 1.5 SDK signaling: send member state event via GroupCallSession
      await _enterGroupCallSignaling(roomId, wsUrl);

      // 2. Create and connect to the LiveKit Room
      Logs().i('[LiveKit] Connecting to $wsUrl...');
      _livekitRoom = lk.Room();
      _setupRoomListeners();

      await _livekitRoom!.connect(
        wsUrl,
        jwt,
        roomOptions: lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: const lk.AudioPublishOptions(
            name: 'microphone',
          ),
          defaultVideoPublishOptions: const lk.VideoPublishOptions(
            name: 'camera',
          ),
        ),
      );

      // 3. Publish local tracks
      Logs().i('[LiveKit] Publishing local tracks...');
      await _livekitRoom!.localParticipant?.setMicrophoneEnabled(true);
      if (isVideo) {
        await _livekitRoom!.localParticipant?.setCameraEnabled(true);
      }

      _setCallState(LiveKitCallState.connected);
      Logs().i('[LiveKit] Call connected successfully');
    } catch (e, stack) {
      Logs().e('[LiveKit] Failed to start call', e, stack);
      lastError = e.toString();
      _setCallState(LiveKitCallState.ended);
      await _leaveGroupCallSignaling();
      await _cleanupRoom();
    }
  }

  /// Hang up / disconnect the current call.
  Future<void> hangUp() async {
    if (_callState == LiveKitCallState.idle ||
        _callState == LiveKitCallState.ended) {
      return;
    }
    _setCallState(LiveKitCallState.ending);
    await _cleanupRoom();
    await _leaveGroupCallSignaling();
    _setCallState(LiveKitCallState.ended);
  }

  /// Toggle the microphone mute state.
  Future<void> toggleMicrophone() async {
    if (_livekitRoom?.localParticipant == null) return;
    _isMicMuted = !_isMicMuted;
    await _livekitRoom!.localParticipant!.setMicrophoneEnabled(!_isMicMuted);
    onTracksChanged.add(null);
  }

  /// Toggle the camera on/off.
  Future<void> toggleCamera() async {
    if (_livekitRoom?.localParticipant == null) return;
    _isCamDisabled = !_isCamDisabled;
    await _livekitRoom!.localParticipant!.setCameraEnabled(!_isCamDisabled);
    onTracksChanged.add(null);
  }

  /// Switch between front and back camera.
  Future<void> switchCamera() async {
    // Find local video track publication
    final publications = _livekitRoom?.localParticipant?.videoTrackPublications;
    if (publications == null || publications.isEmpty) return;
    
    for (final pub in publications) {
      final track = pub.track;
      if (track is lk.LocalVideoTrack) {
        // Get current camera position and switch
        final options = track.currentOptions;
        if (options is lk.CameraCaptureOptions) {
          final newPosition = options.cameraPosition == lk.CameraPosition.front
              ? lk.CameraPosition.back
              : lk.CameraPosition.front;
          await track.setCameraPosition(newPosition);
        }
        break;
      }
    }
  }

  /// Whether we are in an active call (connecting or connected).
  bool get isInCall =>
      _callState == LiveKitCallState.connecting ||
      _callState == LiveKitCallState.connected;

  /// Get the local video track (if any).
  lk.VideoTrack? get localVideoTrack {
    try {
      final pub = _livekitRoom?.localParticipant?.videoTrackPublications
          .firstWhere((p) => p.track != null);
      return pub?.track as lk.VideoTrack?;
    } catch (_) {
      return null;
    }
  }

  /// Get the first remote participant's video track (1:1 call).
  lk.VideoTrack? get remoteVideoTrack {
    try {
      final remoteParticipant = _livekitRoom?.remoteParticipants.values.first;
      final pub = remoteParticipant?.videoTrackPublications
          .firstWhere((p) => p.track != null);
      return pub?.track as lk.VideoTrack?;
    } catch (_) {
      return null;
    }
  }

  /// Get the first remote participant's audio track (1:1 call).
  lk.AudioTrack? get remoteAudioTrack {
    try {
      final remoteParticipant = _livekitRoom?.remoteParticipants.values.first;
      final pub = remoteParticipant?.audioTrackPublications
          .firstWhere((p) => p.track != null);
      return pub?.track as lk.AudioTrack?;
    } catch (_) {
      return null;
    }
  }

  /// Whether there is a remote participant connected.
  bool get hasRemoteParticipant =>
      _livekitRoom != null &&
      _livekitRoom!.remoteParticipants.isNotEmpty;

  /// Reset plugin to idle state (e.g. after call ended and UI dismissed).
  void reset() {
    _callState = LiveKitCallState.idle;
    _currentRoomId = null;
    _groupCallSession = null;
    lastError = null;
  }

  /// Dispose all resources.
  void dispose() {
    onCallStateChanged.close();
    onTracksChanged.close();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _setCallState(LiveKitCallState state) {
    _callState = state;
    onCallStateChanged.add(state);
  }

  void _setupRoomListeners() {
    if (_livekitRoom == null) return;

    _listener = _livekitRoom!.createListener();

    _listener!.on<lk.TrackSubscribedEvent>((e) {
      Logs().i('[LiveKit] Track subscribed: ${e.track.sid}');
      onTracksChanged.add(null);
    });

    _listener!.on<lk.TrackUnsubscribedEvent>((e) {
      Logs().i('[LiveKit] Track unsubscribed: ${e.track.sid}');
      onTracksChanged.add(null);
    });

    _listener!.on<lk.LocalTrackPublishedEvent>((e) {
      Logs().i('[LiveKit] Local track published');
      onTracksChanged.add(null);
    });

    _listener!.on<lk.LocalTrackUnpublishedEvent>((e) {
      Logs().i('[LiveKit] Local track unpublished');
      onTracksChanged.add(null);
    });

    _listener!.on<lk.ParticipantConnectedEvent>((e) {
      Logs().i('[LiveKit] Participant connected: ${e.participant.identity}');
      onTracksChanged.add(null);
    });

    _listener!.on<lk.ParticipantDisconnectedEvent>((e) {
      Logs().i('[LiveKit] Participant disconnected: ${e.participant.identity}');
      onTracksChanged.add(null);
    });

    _listener!.on<lk.RoomDisconnectedEvent>((e) {
      Logs().i('[LiveKit] Room disconnected');
      if (_callState == LiveKitCallState.connected) {
        _setCallState(LiveKitCallState.ended);
        _cleanupRoom();
      }
    });
  }

  Future<void> _cleanupRoom() async {
    try {
      await _listener?.dispose();
      _listener = null;

      if (_livekitRoom != null) {
        await _livekitRoom!.disconnect();
        await _livekitRoom!.dispose();
      }
    } catch (e) {
      Logs().w('[LiveKit] Cleanup error: $e');
    }
    _livekitRoom = null;
  }

  // ---------------------------------------------------------------------------
  // SDK MatrixRTC signaling helpers
  // ---------------------------------------------------------------------------

  /// Enter the GroupCallSession to send member state event to the room.
  Future<void> _enterGroupCallSignaling(
    String roomId,
    String livekitServiceUrl,
  ) async {
    if (voip == null) return;
    final room = client.getRoomById(roomId);
    if (room == null) {
      Logs().w('[LiveKit] Cannot find room $roomId for signaling');
      return;
    }
    try {
      _groupCallSession = await voip!.fetchOrCreateGroupCall(
        roomId,
        room,
        LiveKitBackend(
          livekitServiceUrl: livekitServiceUrl,
          livekitAlias: roomId,
          e2eeEnabled: false,
        ),
        'm.call',
        'm.room',
      );
      await _groupCallSession!.enter();
      Logs().i('[LiveKit] SDK signaling: entered group call for $roomId');
    } catch (e, s) {
      Logs().e('[LiveKit] SDK signaling: failed to enter group call', e, s);
      // Non-fatal: call can still work without signaling
    }
  }

  /// Leave the GroupCallSession to remove member state event.
  Future<void> _leaveGroupCallSignaling() async {
    if (_groupCallSession == null) return;
    try {
      await _groupCallSession!.leave();
      Logs().i('[LiveKit] SDK signaling: left group call');
    } catch (e, s) {
      Logs().e('[LiveKit] SDK signaling: failed to leave group call', e, s);
    }
    _groupCallSession = null;
  }
}
