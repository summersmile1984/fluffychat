import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:fluffychat/utils/voip/livekit_plugin.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'pip/pip_view.dart';

/// A full-screen 1:1 LiveKit call page.
///
/// Shows local and remote video tracks, call state indicators,
/// and action buttons (mute mic, toggle camera, switch camera, hang up).
class LiveKitCallPage extends StatefulWidget {
  final LiveKitPlugin liveKitPlugin;
  final Client client;
  final Room room;
  final VoidCallback? onClear;

  const LiveKitCallPage({
    required this.liveKitPlugin,
    required this.client,
    required this.room,
    this.onClear,
    super.key,
  });

  @override
  State<LiveKitCallPage> createState() => _LiveKitCallPageState();
}

class _LiveKitCallPageState extends State<LiveKitCallPage> {
  LiveKitPlugin get plugin => widget.liveKitPlugin;

  StreamSubscription? _stateSubscription;
  StreamSubscription? _trackSubscription;

  @override
  void initState() {
    super.initState();
    _stateSubscription = plugin.onCallStateChanged.stream.listen((_) {
      if (mounted) setState(() {});
      if (plugin.callState == LiveKitCallState.ended) {
        _onCallEnded();
      }
    });
    _trackSubscription = plugin.onTracksChanged.stream.listen((_) {
      if (mounted) setState(() {});
    });

    // Keep screen on during calls
    try {
      WakelockPlus.enable();
    } catch (_) {}
  }

  void _onCallEnded() {
    try {
      WakelockPlus.disable();
    } catch (_) {}
    // Delay slightly so the user can see "Call Ended" text
    Future.delayed(const Duration(seconds: 2), () {
      widget.onClear?.call();
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _trackSubscription?.cancel();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    super.dispose();
  }

  void _hangUp() {
    HapticFeedback.heavyImpact();
    plugin.hangUp();
  }

  void _toggleMic() {
    setState(() {});
    plugin.toggleMicrophone();
  }

  void _toggleCamera() {
    setState(() {});
    plugin.toggleCamera();
  }

  void _switchCamera() {
    plugin.switchCamera();
  }

  /// Display name for the remote user (1:1 call).
  String get _roomDisplayName {
    return widget.room.getLocalizedDisplayname();
  }

  Uri? get _roomAvatarUrl {
    return widget.room.avatar;
  }

  @override
  Widget build(BuildContext context) {
    return PIPView(
      builder: (context, isFloating) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Remote video / avatar
              _buildRemoteView(),

              // Local video (small PiP in corner)
              if (!isFloating && plugin.callState == LiveKitCallState.connected)
                _buildLocalVideoOverlay(),

              // Status overlay (connecting / ended)
              if (plugin.callState != LiveKitCallState.connected)
                _buildStatusOverlay(),

              // Action buttons
              if (!isFloating) _buildActionBar(),

              // Minimize button
              if (!isFloating)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      PIPView.of(context)?.setFloating(true);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRemoteView() {
    final remoteVideo = plugin.remoteVideoTrack;
    if (remoteVideo != null) {
      return lk.VideoTrackRenderer(
        remoteVideo,
        fit: lk.VideoViewFit.contain,
      );
    }

    // No remote video — show avatar with dark background
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(
              mxContent: _roomAvatarUrl,
              name: _roomDisplayName,
              size: 96,
              client: widget.client,
            ),
            const SizedBox(height: 16),
            Text(
              _roomDisplayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalVideoOverlay() {
    final localVideo = plugin.localVideoTrack;
    if (localVideo == null || plugin.isCamDisabled) return const SizedBox();

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 48,
      right: 16,
      width: 120,
      height: 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: lk.VideoTrackRenderer(
            localVideo,
            fit: lk.VideoViewFit.cover,
            mirrorMode: lk.VideoViewMirrorMode.mirror,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOverlay() {
    String statusText;
    IconData statusIcon;

    switch (plugin.callState) {
      case LiveKitCallState.connecting:
        statusText = '正在连接...';
        statusIcon = Icons.call;
        break;
      case LiveKitCallState.ending:
        statusText = '正在挂断...';
        statusIcon = Icons.call_end;
        break;
      case LiveKitCallState.ended:
        statusText = plugin.lastError != null ? '通话失败' : '通话结束';
        statusIcon = Icons.call_end;
        break;
      default:
        statusText = '';
        statusIcon = Icons.call;
    }

    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (plugin.callState == LiveKitCallState.connecting)
              const CircularProgressIndicator(color: Colors.white),
            if (plugin.callState != LiveKitCallState.connecting)
              Icon(statusIcon, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              statusText,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            if (plugin.lastError != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  plugin.lastError!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    final isConnected = plugin.callState == LiveKitCallState.connected;
    final isActive = plugin.callState == LiveKitCallState.connecting ||
        plugin.callState == LiveKitCallState.connected;

    return Positioned(
      bottom: MediaQuery.paddingOf(context).bottom + 32,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (isConnected) ...[
            // Mic toggle
            _ActionButton(
              icon: plugin.isMicMuted ? Icons.mic_off : Icons.mic,
              label: plugin.isMicMuted ? '取消静音' : '静音',
              onPressed: _toggleMic,
              isActive: !plugin.isMicMuted,
            ),
            // Camera toggle
            if (plugin.isVideoCall)
              _ActionButton(
                icon: plugin.isCamDisabled
                    ? Icons.videocam_off
                    : Icons.videocam,
                label: plugin.isCamDisabled ? '开启相机' : '关闭相机',
                onPressed: _toggleCamera,
                isActive: !plugin.isCamDisabled,
              ),
            // Switch camera
            if (plugin.isVideoCall)
              _ActionButton(
                icon: Icons.switch_camera,
                label: '切换',
                onPressed: _switchCamera,
              ),
          ],
          // Hang up
          if (isActive)
            _ActionButton(
              icon: Icons.call_end,
              label: '挂断',
              onPressed: _hangUp,
              backgroundColor: Colors.red,
            ),
          // Dismiss after ended
          if (plugin.callState == LiveKitCallState.ended)
            _ActionButton(
              icon: Icons.close,
              label: '关闭',
              onPressed: () => widget.onClear?.call(),
            ),
        ],
      ),
    );
  }
}

/// A circular action button used in the call UI.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isActive;
  final Color? backgroundColor;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? (isActive ? Colors.white24 : Colors.white);
    final fgColor = isActive ? Colors.white : Colors.black87;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: label,
          onPressed: onPressed,
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          elevation: 4,
          child: Icon(icon),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
