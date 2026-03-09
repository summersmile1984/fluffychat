import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

import 'matrix_rtc_manager.dart';

/// State of a group call.
enum LkGroupCallState {
  /// No active group call.
  idle,

  /// Requesting JWT and connecting.
  connecting,

  /// Connected to LiveKit room.
  connected,

  /// Disconnecting.
  ending,

  /// Call ended.
  ended,
}

/// Manages a multi-participant LiveKit-based group call with SDK MatrixRTC
/// signaling.
///
/// Handles:
/// - SDK [GroupCallSession] for member state events (signaling layer)
/// - LiveKit Room connection and multi-participant track management (media layer)
/// - State, participant, and track change notifications for the UI
class GroupCallPlugin {
  final Client client;
  late final MatrixRTCManager _rtcManager;

  lk.Room? _livekitRoom;
  lk.EventsListener<lk.RoomEvent>? _listener;

  /// SDK GroupCallSession for MatrixRTC signaling.
  GroupCallSession? _groupCallSession;

  /// Current call state.
  LkGroupCallState _callState = LkGroupCallState.idle;
  LkGroupCallState get callState => _callState;

  /// The Matrix room of the current call.
  Room? _matrixRoom;
  Room? get matrixRoom => _matrixRoom;

  /// Whether the call includes video.
  bool _isVideoCall = false;
  bool get isVideoCall => _isVideoCall;

  /// Whether the local microphone is muted.
  bool _isMicMuted = false;
  bool get isMicMuted => _isMicMuted;

  /// Whether the local camera is disabled.
  bool _isCamDisabled = false;
  bool get isCamDisabled => _isCamDisabled;

  /// Stream of call state changes.
  final StreamController<LkGroupCallState> onCallStateChanged =
      StreamController<LkGroupCallState>.broadcast();

  /// Stream of track / participant updates for UI refresh.
  final StreamController<void> onParticipantsChanged =
      StreamController<void>.broadcast();

  /// Error message if the call failed.
  String? lastError;

  /// Call duration timer.
  DateTime? _callStartTime;
  DateTime? get callStartTime => _callStartTime;

  GroupCallPlugin({required this.client}) {
    _rtcManager = MatrixRTCManager(client: client);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Start or join a group call in the given Matrix [room].
  /// [voip] is required for SDK signaling.
  Future<void> startCall(
    Room room,
    VoIP voip, {
    bool isVideo = true,
  }) async {
    if (_callState != LkGroupCallState.idle &&
        _callState != LkGroupCallState.ended) {
      Logs().w('[GroupCall] Cannot start — already in state $_callState');
      return;
    }

    _matrixRoom = room;
    _isVideoCall = isVideo;
    _isMicMuted = false;
    _isCamDisabled = false;
    lastError = null;
    _setCallState(LkGroupCallState.connecting);

    try {
      // 1. Get LiveKit JWT token
      Logs().i('[GroupCall] Requesting JWT for room ${room.id}...');
      final jwt = await _rtcManager.getLivekitJwt(room.id);
      final wsUrl = _rtcManager.lastLivekitUrl;

      if (wsUrl == null || wsUrl.isEmpty) {
        throw Exception('LiveKit WS URL not returned by server');
      }

      // 2. SDK signaling: create/join GroupCallSession and send member event
      try {
        _groupCallSession = await voip.fetchOrCreateGroupCall(
          room.id,
          room,
          LiveKitBackend(
            livekitServiceUrl: wsUrl,
            livekitAlias: room.id,
            e2eeEnabled: false,
          ),
          'm.call',
          'm.room',
        );
        await _groupCallSession!.enter();
        Logs().i('[GroupCall] SDK signaling: entered group call for ${room.id}');
      } catch (e, s) {
        Logs().e('[GroupCall] SDK signaling failed (non-fatal)', e, s);
        // Continue — media can still work without signaling
      }

      // 3. Connect to LiveKit Room
      Logs().i('[GroupCall] Connecting to $wsUrl...');
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

      // 4. Publish local tracks
      Logs().i('[GroupCall] Publishing local tracks...');
      await _livekitRoom!.localParticipant?.setMicrophoneEnabled(true);
      if (isVideo) {
        await _livekitRoom!.localParticipant?.setCameraEnabled(true);
      }

      _callStartTime = DateTime.now();
      _setCallState(LkGroupCallState.connected);
      Logs().i('[GroupCall] Connected successfully');
    } catch (e, stack) {
      Logs().e('[GroupCall] Failed to start call', e, stack);
      lastError = e.toString();
      _setCallState(LkGroupCallState.ended);
      await _leaveSignaling();
      await _cleanupRoom();
    }
  }

  /// Hang up / leave the group call.
  Future<void> hangUp() async {
    if (_callState == LkGroupCallState.idle ||
        _callState == LkGroupCallState.ended) {
      return;
    }
    _setCallState(LkGroupCallState.ending);
    await _cleanupRoom();
    await _leaveSignaling();
    _callStartTime = null;
    _setCallState(LkGroupCallState.ended);
  }

  /// Toggle the microphone mute state.
  Future<void> toggleMicrophone() async {
    if (_livekitRoom?.localParticipant == null) return;
    _isMicMuted = !_isMicMuted;
    await _livekitRoom!.localParticipant!.setMicrophoneEnabled(!_isMicMuted);
    onParticipantsChanged.add(null);
  }

  /// Toggle the camera on/off.
  Future<void> toggleCamera() async {
    if (_livekitRoom?.localParticipant == null) return;
    _isCamDisabled = !_isCamDisabled;
    await _livekitRoom!.localParticipant!.setCameraEnabled(!_isCamDisabled);
    onParticipantsChanged.add(null);
  }

  /// Switch between front and back camera.
  Future<void> switchCamera() async {
    final publications = _livekitRoom?.localParticipant?.videoTrackPublications;
    if (publications == null || publications.isEmpty) return;

    for (final pub in publications) {
      final track = pub.track;
      if (track is lk.LocalVideoTrack) {
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

  /// Whether we are in an active call.
  bool get isInCall =>
      _callState == LkGroupCallState.connecting ||
      _callState == LkGroupCallState.connected;

  // ---------------------------------------------------------------------------
  // Participant queries
  // ---------------------------------------------------------------------------

  /// All remote participants in the LiveKit room.
  Map<String, lk.RemoteParticipant> get remoteParticipants =>
      _livekitRoom?.remoteParticipants ?? {};

  /// The local participant.
  lk.LocalParticipant? get localParticipant =>
      _livekitRoom?.localParticipant;

  /// Total participant count (local + remote).
  int get participantCount =>
      1 + remoteParticipants.length;

  /// Get the first video track for a participant.
  lk.VideoTrack? getVideoTrack(lk.Participant participant) {
    try {
      final pub = participant.videoTrackPublications
          .firstWhere((p) => p.track != null);
      return pub.track as lk.VideoTrack?;
    } catch (_) {
      return null;
    }
  }

  /// Check if a participant has their microphone muted.
  bool isParticipantMuted(lk.Participant participant) {
    try {
      final pub = participant.audioTrackPublications.first;
      return pub.muted;
    } catch (_) {
      return true;
    }
  }

  /// Check if a participant is currently speaking.
  bool isParticipantSpeaking(lk.Participant participant) {
    return participant.isSpeaking;
  }

  /// Get a display identity for a remote participant.
  String getParticipantDisplayName(lk.Participant participant) {
    final identity = participant.identity.toString();
    // identity is typically the Matrix user ID
    if (identity.startsWith('@')) {
      // Extract localpart: @user:server → user
      final colon = identity.indexOf(':');
      if (colon > 1) {
        return identity.substring(1, colon);
      }
    }
    return identity.isNotEmpty ? identity : 'Unknown';
  }

  /// Reset the plugin to idle state.
  void reset() {
    _callState = LkGroupCallState.idle;
    _matrixRoom = null;
    _groupCallSession = null;
    _callStartTime = null;
    lastError = null;
  }

  /// Dispose all resources.
  void dispose() {
    onCallStateChanged.close();
    onParticipantsChanged.close();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _setCallState(LkGroupCallState state) {
    _callState = state;
    onCallStateChanged.add(state);
  }

  void _setupRoomListeners() {
    if (_livekitRoom == null) return;

    _listener = _livekitRoom!.createListener();

    _listener!.on<lk.TrackSubscribedEvent>((e) {
      Logs().i('[GroupCall] Track subscribed: ${e.track.sid}');
      onParticipantsChanged.add(null);
    });

    _listener!.on<lk.TrackUnsubscribedEvent>((e) {
      Logs().i('[GroupCall] Track unsubscribed: ${e.track.sid}');
      onParticipantsChanged.add(null);
    });

    _listener!.on<lk.LocalTrackPublishedEvent>((e) {
      Logs().i('[GroupCall] Local track published');
      onParticipantsChanged.add(null);
    });

    _listener!.on<lk.LocalTrackUnpublishedEvent>((e) {
      Logs().i('[GroupCall] Local track unpublished');
      onParticipantsChanged.add(null);
    });

    _listener!.on<lk.ParticipantConnectedEvent>((e) {
      Logs().i(
        '[GroupCall] Participant connected: ${e.participant.identity}',
      );
      onParticipantsChanged.add(null);
    });

    _listener!.on<lk.ParticipantDisconnectedEvent>((e) {
      Logs().i(
        '[GroupCall] Participant disconnected: ${e.participant.identity}',
      );
      onParticipantsChanged.add(null);
    });

    _listener!.on<lk.ActiveSpeakersChangedEvent>((e) {
      onParticipantsChanged.add(null);
    });

    _listener!.on<lk.TrackMutedEvent>((e) {
      onParticipantsChanged.add(null);
    });

    _listener!.on<lk.TrackUnmutedEvent>((e) {
      onParticipantsChanged.add(null);
    });

    _listener!.on<lk.RoomDisconnectedEvent>((e) {
      Logs().i('[GroupCall] Room disconnected');
      if (_callState == LkGroupCallState.connected) {
        _setCallState(LkGroupCallState.ended);
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
      Logs().w('[GroupCall] Cleanup error: $e');
    }
    _livekitRoom = null;
  }

  Future<void> _leaveSignaling() async {
    if (_groupCallSession == null) return;
    try {
      await _groupCallSession!.leave();
      Logs().i('[GroupCall] SDK signaling: left group call');
    } catch (e, s) {
      Logs().e('[GroupCall] SDK signaling: failed to leave', e, s);
    }
    _groupCallSession = null;
  }
}
