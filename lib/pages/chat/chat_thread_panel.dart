import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_event_list.dart';
import 'package:fluffychat/pages/chat/chat_emoji_picker.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/pages/chat/reply_display.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';

/// A side panel that displays a message thread on desktop (column mode).
/// Shares the same [ChatController] as the main chat view so all state
/// (timeline, sending client, reply/edit events, emoji picker, etc.)
/// is shared.
class ChatThreadPanel extends StatelessWidget {
  final ChatController controller;

  const ChatThreadPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeThreadId = controller.activeThreadId;

    // Resolve the thread root event for the header
    final threadRootEvent = controller.timeline?.events
        .firstWhere(
          (e) => e.eventId == activeThreadId,
          orElse: () => Event(
            eventId: activeThreadId ?? '',
            content: {'msgtype': 'm.text', 'body': '...'},
            senderId: '',
            type: 'm.room.message',
            room: controller.room,
            status: EventStatus.sent,
            originServerTs: DateTime.now(),
          ),
        );


    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: theme.colorScheme.secondaryContainer,
        toolbarHeight: 56,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: controller.closeThread,
          tooltip: L10n.of(context).close,
          color: theme.colorScheme.onSecondaryContainer,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.of(context).thread,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            if (threadRootEvent != null)
              Text(
                threadRootEvent.calcLocalizedBodyFallback(
                  MatrixLocals(L10n.of(context)),
                  withSenderNamePrefix: true,
                  hideReply: true,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSecondaryContainer.withAlpha(179),
                ),
              ),
          ],
        ),
        actions: [
          if (activeThreadId != null)
            IconButton(
              icon: const Icon(Icons.shortcut_outlined),
              tooltip: L10n.of(context).replyInThread,
              onPressed: () => controller.scrollToEventId(activeThreadId),
              color: theme.colorScheme.onSecondaryContainer,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: controller.clearSingleSelectedEvent,
                child: ChatEventList(controller: controller),
              ),
            ),
            if (controller.room.canSendDefaultMessages &&
                controller.room.membership == Membership.join)
              Container(
                margin: const EdgeInsets.all(8.0),
                constraints: const BoxConstraints(
                  maxWidth: FluffyThemes.maxTimelineWidth,
                ),
                alignment: Alignment.center,
                child: Material(
                  clipBehavior: Clip.hardEdge,
                  color: controller.selectedEvents.isNotEmpty
                      ? theme.colorScheme.tertiaryContainer
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReplyDisplay(controller),
                      ChatInputRow(controller),
                      ChatEmojiPicker(controller),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
