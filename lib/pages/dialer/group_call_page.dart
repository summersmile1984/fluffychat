import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/voip/group_call_plugin.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// A full-screen multi-participant LiveKit group call page.
///
/// Responsive layout:
/// - Mobile (< 840px): main video + horizontal thumbnail strip + action bar
/// - Desktop (≥ 840px): video grid + side participant panel + action bar
class GroupCallPage extends StatefulWidget {
  final GroupCallPlugin plugin;
  final Client client;
  final Room room;
  final VoidCallback? onClear;

  const GroupCallPage({
    required this.plugin,
    required this.client,
    required this.room,
    this.onClear,
    super.key,
  });

  @override
  State<GroupCallPage> createState() => _GroupCallPageState();
}

class _GroupCallPageState extends State<GroupCallPage> {
  GroupCallPlugin get plugin => widget.plugin;

  StreamSubscription? _stateSubscription;
  StreamSubscription? _participantSubscription;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _stateSubscription = plugin.onCallStateChanged.stream.listen((_) {
      if (mounted) setState(() {});
      if (plugin.callState == LkGroupCallState.ended) {
        _onCallEnded();
      }
    });
    _participantSubscription = plugin.onParticipantsChanged.stream.listen((_) {
      if (mounted) setState(() {});
    });

    // Timer for call duration display
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && plugin.callState == LkGroupCallState.connected) {
        setState(() {});
      }
    });

    try {
      WakelockPlus.enable();
    } catch (_) {}
  }

  void _onCallEnded() {
    try {
      WakelockPlus.disable();
    } catch (_) {}
    Future.delayed(const Duration(seconds: 2), () {
      widget.onClear?.call();
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _participantSubscription?.cancel();
    _durationTimer?.cancel();
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
    plugin.toggleMicrophone();
  }

  void _toggleCamera() {
    plugin.toggleCamera();
  }

  void _switchCamera() {
    plugin.switchCamera();
  }

  String get _durationText {
    if (plugin.callStartTime == null) return '';
    final dur = DateTime.now().difference(plugin.callStartTime!);
    final mins = dur.inMinutes.toString().padLeft(2, '0');
    final secs = (dur.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = FluffyThemes.isColumnMode(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            _buildTopBar(),
            // Main content
            Expanded(
              child: plugin.callState == LkGroupCallState.connected
                  ? (isDesktop
                      ? _buildDesktopLayout()
                      : _buildMobileLayout())
                  : _buildStatusOverlay(),
            ),
            // Action bar
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top Bar
  // ---------------------------------------------------------------------------

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF16213E),
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups, color: Colors.white70, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.room.getLocalizedDisplayname(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (plugin.callState == LkGroupCallState.connected) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, color: Colors.white54, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${plugin.participantCount}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _durationText,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile Layout: main speaker + thumbnail strip
  // ---------------------------------------------------------------------------

  Widget _buildMobileLayout() {
    final allParticipants = _getAllParticipants();
    if (allParticipants.isEmpty) return _buildEmptyState();

    if (allParticipants.length <= 4) {
      // Grid view for small number of participants
      return _buildVideoGrid(allParticipants, crossAxisCount: allParticipants.length <= 2 ? 1 : 2);
    }

    // Main speaker + thumbnail strip for 5+ participants
    final mainParticipant = allParticipants.first;
    final thumbnailParticipants = allParticipants.sublist(1);

    return Column(
      children: [
        // Main video
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _ParticipantTile(
              participant: mainParticipant,
              plugin: plugin,
              client: widget.client,
              room: widget.room,
              showName: true,
            ),
          ),
        ),
        // Thumbnail strip
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: thumbnailParticipants.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 120,
                  child: _ParticipantTile(
                    participant: thumbnailParticipants[index],
                    plugin: plugin,
                    client: widget.client,
                    room: widget.room,
                    showName: true,
                    compact: true,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop Layout: video grid + side panel
  // ---------------------------------------------------------------------------

  Widget _buildDesktopLayout() {
    final allParticipants = _getAllParticipants();
    if (allParticipants.isEmpty) return _buildEmptyState();

    return Row(
      children: [
        // Main video grid
        Expanded(
          child: _buildVideoGrid(
            allParticipants,
            crossAxisCount: _getGridColumns(allParticipants.length),
          ),
        ),
        // Side participant panel
        Container(
          width: 200,
          decoration: const BoxDecoration(
            color: Color(0xFF0F3460),
            border: Border(left: BorderSide(color: Colors.white12)),
          ),
          child: _buildParticipantPanel(allParticipants),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Video Grid
  // ---------------------------------------------------------------------------

  Widget _buildVideoGrid(
    List<lk.Participant> participants, {
    required int crossAxisCount,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 16 / 10,
        ),
        itemCount: participants.length,
        itemBuilder: (context, index) {
          return _ParticipantTile(
            participant: participants[index],
            plugin: plugin,
            client: widget.client,
            room: widget.room,
            showName: true,
          );
        },
      ),
    );
  }

  int _getGridColumns(int count) {
    if (count <= 1) return 1;
    if (count <= 4) return 2;
    if (count <= 9) return 3;
    return 4;
  }

  // ---------------------------------------------------------------------------
  // Participant Panel (Desktop)
  // ---------------------------------------------------------------------------

  Widget _buildParticipantPanel(List<lk.Participant> participants) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '参与者',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: participants.length,
            itemBuilder: (context, index) {
              final p = participants[index];
              final isLocal = p is lk.LocalParticipant;
              final displayName = isLocal
                  ? '我'
                  : plugin.getParticipantDisplayName(p);
              final isMuted = plugin.isParticipantMuted(p);
              final isSpeaking = plugin.isParticipantSpeaking(p);

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSpeaking ? Colors.white.withAlpha(15) : null,
                ),
                child: Row(
                  children: [
                    Avatar(
                      mxContent: isLocal ? null : widget.room.avatar,
                      name: displayName,
                      size: 32,
                      client: widget.client,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          color: isSpeaking ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: isSpeaking
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      isMuted ? Icons.mic_off : Icons.mic,
                      size: 16,
                      color: isMuted ? Colors.red.shade300 : Colors.green.shade300,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Status Overlay (connecting / ended)
  // ---------------------------------------------------------------------------

  Widget _buildStatusOverlay() {
    String statusText;
    IconData statusIcon;

    switch (plugin.callState) {
      case LkGroupCallState.connecting:
        statusText = '正在连接...';
        statusIcon = Icons.groups;
        break;
      case LkGroupCallState.ending:
        statusText = '正在离开...';
        statusIcon = Icons.call_end;
        break;
      case LkGroupCallState.ended:
        statusText = plugin.lastError != null ? '会议连接失败' : '会议已结束';
        statusIcon = Icons.call_end;
        break;
      default:
        statusText = '';
        statusIcon = Icons.groups;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (plugin.callState == LkGroupCallState.connecting)
            const CircularProgressIndicator(color: Colors.white),
          if (plugin.callState != LkGroupCallState.connecting)
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
    );
  }

  // ---------------------------------------------------------------------------
  // Action Bar
  // ---------------------------------------------------------------------------

  Widget _buildActionBar() {
    final isConnected = plugin.callState == LkGroupCallState.connected;
    final isActive = plugin.callState == LkGroupCallState.connecting ||
        plugin.callState == LkGroupCallState.connected;

    return Container(
      padding: EdgeInsets.only(
        bottom: 16,
        top: 12,
        left: 16,
        right: 16,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF16213E),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (isConnected) ...[
            _ActionButton(
              icon: plugin.isMicMuted ? Icons.mic_off : Icons.mic,
              label: plugin.isMicMuted ? '取消静音' : '静音',
              onPressed: _toggleMic,
              isActive: !plugin.isMicMuted,
            ),
            if (plugin.isVideoCall)
              _ActionButton(
                icon: plugin.isCamDisabled
                    ? Icons.videocam_off
                    : Icons.videocam,
                label: plugin.isCamDisabled ? '开启相机' : '关闭相机',
                onPressed: _toggleCamera,
                isActive: !plugin.isCamDisabled,
              ),
            if (plugin.isVideoCall)
              _ActionButton(
                icon: Icons.switch_camera,
                label: '翻转',
                onPressed: _switchCamera,
              ),
          ],
          if (isActive)
            _ActionButton(
              icon: Icons.call_end,
              label: '离开',
              onPressed: _hangUp,
              backgroundColor: Colors.red,
            ),
          if (plugin.callState == LkGroupCallState.ended)
            _ActionButton(
              icon: Icons.close,
              label: '关闭',
              onPressed: () => widget.onClear?.call(),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, color: Colors.white24, size: 64),
          SizedBox(height: 16),
          Text(
            '等待其他参与者加入...',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Get all participants (local first, then remotes sorted by speaking).
  List<lk.Participant> _getAllParticipants() {
    final local = plugin.localParticipant;
    // Add remote participants, speaking ones first
    final remotes = plugin.remoteParticipants.values.toList()
      ..sort((a, b) {
        if (a.isSpeaking && !b.isSpeaking) return -1;
        if (!a.isSpeaking && b.isSpeaking) return 1;
        return 0;
      });
    final List<lk.Participant> result = List.from(remotes);
    // Local participant last
    if (local != null) result.add(local);
    return result;
  }
}

// =============================================================================
// Participant Tile
// =============================================================================

/// A single participant's video/avatar tile.
class _ParticipantTile extends StatelessWidget {
  final lk.Participant participant;
  final GroupCallPlugin plugin;
  final Client client;
  final Room room;
  final bool showName;
  final bool compact;

  const _ParticipantTile({
    required this.participant,
    required this.plugin,
    required this.client,
    required this.room,
    this.showName = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLocal = participant is lk.LocalParticipant;
    final videoTrack = plugin.getVideoTrack(participant);
    final isMuted = plugin.isParticipantMuted(participant);
    final isSpeaking = plugin.isParticipantSpeaking(participant);
    final displayName = isLocal
        ? '我'
        : plugin.getParticipantDisplayName(participant);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F3460),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSpeaking
              ? Colors.greenAccent.withAlpha(180)
              : Colors.white.withAlpha(20),
          width: isSpeaking ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video or avatar
          if (videoTrack != null)
            lk.VideoTrackRenderer(
              videoTrack,
              fit: lk.VideoViewFit.cover,
              mirrorMode: isLocal
                  ? lk.VideoViewMirrorMode.mirror
                  : lk.VideoViewMirrorMode.off,
            )
          else
            Center(
              child: Avatar(
                mxContent: isLocal ? null : room.avatar,
                name: displayName,
                size: compact ? 36 : 64,
                client: client,
              ),
            ),

          // Name + mic indicator overlay
          if (showName)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 11 : 13,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      isMuted ? Icons.mic_off : Icons.mic,
                      size: compact ? 12 : 14,
                      color: isMuted
                          ? Colors.red.shade300
                          : Colors.green.shade300,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Action Button
// =============================================================================

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
    final bgColor =
        backgroundColor ?? (isActive ? Colors.white24 : Colors.white);
    final fgColor = isActive ? Colors.white : Colors.black87;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'group_call_$label',
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
