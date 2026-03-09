import 'dart:core';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc_impl;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart' hide Navigator;

import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/dialer/dialer.dart';
import 'package:fluffychat/pages/dialer/group_call_page.dart';
import 'package:fluffychat/pages/dialer/livekit_call_page.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/voip/group_call_plugin.dart';
import 'package:fluffychat/utils/voip/livekit_plugin.dart';
import '../../utils/voip/user_media_manager.dart';
import '../widgets/matrix.dart';

class VoipPlugin with WidgetsBindingObserver implements WebRTCDelegate {
  final MatrixState matrix;
  Client get client => matrix.client;
  VoipPlugin(this.matrix) {
    voip = VoIP(client, this);
    liveKitPlugin = LiveKitPlugin(client: client, voip: voip);
    groupCallPlugin = GroupCallPlugin(client: client);
    if (!kIsWeb) {
      final wb = WidgetsBinding.instance;
      wb.addObserver(this);
      didChangeAppLifecycleState(wb.lifecycleState);
    }
  }
  bool background = false;
  bool speakerOn = false;
  late VoIP voip;
  late LiveKitPlugin liveKitPlugin;
  late GroupCallPlugin groupCallPlugin;
  OverlayEntry? overlayEntry;
  BuildContext get context => matrix.context;

  @override
  void didChangeAppLifecycleState(AppLifecycleState? state) {
    background =
        (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused);
  }

  void addCallingOverlay(String callId, CallSession call) {
    final context = kIsWeb
        ? ChatList.contextForVoip!
        : this.context; // web is weird

    if (overlayEntry != null) {
      Logs().e('[VOIP] addCallingOverlay: The call session already exists?');
      overlayEntry!.remove();
    }
    // Overlay.of(context) is broken on web
    // falling back on a dialog
    if (kIsWeb) {
      showDialog(
        context: context,
        builder: (context) => Calling(
          context: context,
          client: client,
          callId: callId,
          call: call,
          onClear: () => Navigator.of(context).pop(),
        ),
      );
    } else {
      overlayEntry = OverlayEntry(
        builder: (_) => Calling(
          context: context,
          client: client,
          callId: callId,
          call: call,
          onClear: () {
            overlayEntry?.remove();
            overlayEntry = null;
          },
        ),
      );
      Overlay.of(context).insert(overlayEntry!);
    }
  }

  @override
  MediaDevices get mediaDevices => webrtc_impl.navigator.mediaDevices;

  @override
  bool get isWeb => kIsWeb;

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) => webrtc_impl.createPeerConnection(configuration, constraints);

  Future<bool> get hasCallingAccount async => false;

  @override
  Future<void> playRingtone() async {
    if (!background && !await hasCallingAccount) {
      try {
        await UserMediaManager().startRingingTone();
      } catch (_) {}
    }
  }

  @override
  Future<void> stopRingtone() async {
    if (!background && !await hasCallingAccount) {
      try {
        await UserMediaManager().stopRingingTone();
      } catch (_) {}
    }
  }

  @override
  Future<void> handleNewCall(CallSession call) async {
    if (PlatformInfos.isAndroid) {
      try {
        final wasForeground = await FlutterForegroundTask.isAppOnForeground;

        await matrix.store.setString(
          'wasForeground',
          wasForeground == true ? 'true' : 'false',
        );
        FlutterForegroundTask.setOnLockScreenVisibility(true);
        FlutterForegroundTask.wakeUpScreen();
        FlutterForegroundTask.launchApp();
      } catch (e) {
        Logs().e('VOIP foreground failed $e');
      }
      // use fallback flutter call pages for outgoing and video calls.
      addCallingOverlay(call.callId, call);
    } else {
      addCallingOverlay(call.callId, call);
    }
  }

  @override
  Future<void> handleCallEnded(CallSession session) async {
    if (overlayEntry != null) {
      overlayEntry!.remove();
      overlayEntry = null;
      if (PlatformInfos.isAndroid) {
        FlutterForegroundTask.setOnLockScreenVisibility(false);
        FlutterForegroundTask.stopService();
        final wasForeground = matrix.store.getString('wasForeground');
        if (wasForeground == 'false') FlutterForegroundTask.minimizeApp();
      }
    }
  }

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {
    Logs().i('[VoIP] Group call ended in ${groupCall.room.id}');
    if (groupCallPlugin.isInCall) {
      await groupCallPlugin.hangUp();
    }
    if (overlayEntry != null) {
      overlayEntry!.remove();
      overlayEntry = null;
    }
  }

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {
    // SDK detected a new group call in a room (another user started it)
    // Currently logged for awareness. Could show a "join call" banner.
    Logs().i('[VoIP] New group call detected in ${groupCall.room.id}');
  }

  @override
  // TODO: implement canHandleNewCall
  bool get canHandleNewCall =>
      voip.currentCID == null && voip.currentGroupCID == null;

  @override
  Future<void> handleMissedCall(CallSession session) async {
    // TODO: implement handleMissedCall
  }

  @override
  // TODO: implement keyProvider
  EncryptionKeyProvider? get keyProvider => throw UnimplementedError();

  @override
  Future<void> registerListeners(CallSession session) {
    // TODO: implement registerListeners
    throw UnimplementedError();
  }

  // ---------------------------------------------------------------------------
  // LiveKit 1:1 Call Integration
  // ---------------------------------------------------------------------------

  /// Start a 1:1 LiveKit call in the given Matrix [room].
  /// Set [isVideo] to true for video, false for audio only.
  Future<void> startLiveKitCall(Room room, {bool isVideo = true}) async {
    if (liveKitPlugin.isInCall) {
      Logs().w('[VoIP] Already in a LiveKit call');
      return;
    }
    liveKitPlugin.reset();
    addLiveKitCallingOverlay(room);
    await liveKitPlugin.startCall(room.id, isVideo: isVideo);
  }

  /// Show the LiveKit call UI as an overlay.
  void addLiveKitCallingOverlay(Room room) {
    final ctx = kIsWeb ? ChatList.contextForVoip! : context;

    if (overlayEntry != null) {
      Logs().e('[VoIP] addLiveKitCallingOverlay: overlay already exists');
      overlayEntry!.remove();
    }

    overlayEntry = OverlayEntry(
      builder: (_) => LiveKitCallPage(
        liveKitPlugin: liveKitPlugin,
        client: client,
        room: room,
        onClear: () {
          overlayEntry?.remove();
          overlayEntry = null;
          liveKitPlugin.reset();
        },
      ),
    );
    Overlay.of(ctx).insert(overlayEntry!);
  }

  // ---------------------------------------------------------------------------
  // Group Call Integration
  // ---------------------------------------------------------------------------

  /// Start or join a multi-participant group call in the given [room].
  Future<void> startGroupCall(Room room, {bool isVideo = true}) async {
    if (groupCallPlugin.isInCall) {
      Logs().w('[VoIP] Already in a group call');
      return;
    }
    groupCallPlugin.reset();
    _addGroupCallOverlay(room);
    await groupCallPlugin.startCall(room, voip, isVideo: isVideo);
  }

  /// Show the group call UI as a full-screen overlay.
  void _addGroupCallOverlay(Room room) {
    final ctx = kIsWeb ? ChatList.contextForVoip! : context;

    if (overlayEntry != null) {
      Logs().e('[VoIP] _addGroupCallOverlay: overlay already exists');
      overlayEntry!.remove();
    }

    overlayEntry = OverlayEntry(
      builder: (_) => GroupCallPage(
        plugin: groupCallPlugin,
        client: client,
        room: room,
        onClear: () {
          overlayEntry?.remove();
          overlayEntry = null;
          groupCallPlugin.reset();
        },
      ),
    );
    Overlay.of(ctx).insert(overlayEntry!);
  }
}
