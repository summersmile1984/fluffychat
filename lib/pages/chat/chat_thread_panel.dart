import 'package:flutter/material.dart';

import 'package:animations/animations.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_event_list.dart';
import 'package:fluffychat/pages/chat/events/reply_content.dart';
import 'package:fluffychat/pages/chat/input_bar.dart';
import 'package:fluffychat/pages/chat/sticker_picker_dialog.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';

/// A side panel that displays a message thread on desktop (column mode).
/// Uses thread-specific input state from [ChatController] so the main
/// chat input and thread input operate independently.
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
                child: ChatEventList(
                  controller: controller,
                  scrollControllerOverride: controller.threadScrollController,
                ),
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
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ThreadReplyDisplay(controller: controller),
                      _ThreadInputRow(controller: controller),
                      _ThreadEmojiPicker(controller: controller),
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

// ---------- Thread-specific reply display ----------

class _ThreadReplyDisplay extends StatelessWidget {
  final ChatController controller;
  const _ThreadReplyDisplay({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      height: controller.threadEditEvent != null ||
              controller.threadReplyEvent != null
          ? 56
          : 0,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: theme.colorScheme.onInverseSurface),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: L10n.of(context).close,
            icon: const Icon(Icons.close),
            onPressed: controller.cancelThreadReplyEventAction,
          ),
          Expanded(
            child: controller.threadReplyEvent != null
                ? ReplyContent(
                    controller.threadReplyEvent!,
                    timeline: controller.timeline,
                  )
                : Text(
                    controller.threadEditEvent != null
                        ? L10n.of(context).edit
                        : '',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------- Thread-specific input row ----------

class _ThreadInputRow extends StatelessWidget {
  final ChatController controller;
  const _ThreadInputRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        const SizedBox(width: 4),
        Container(
          height: 56,
          width: 48,
          alignment: Alignment.center,
          child: IconButton(
            tooltip: L10n.of(context).emojis,
            color: theme.colorScheme.onPrimaryContainer,
            icon: PageTransitionSwitcher(
              transitionBuilder: (
                Widget child,
                Animation<double> primaryAnimation,
                Animation<double> secondaryAnimation,
              ) {
                return SharedAxisTransition(
                  animation: primaryAnimation,
                  secondaryAnimation: secondaryAnimation,
                  transitionType: SharedAxisTransitionType.scaled,
                  fillColor: Colors.transparent,
                  child: child,
                );
              },
              child: Icon(
                controller.threadShowEmojiPicker
                    ? Icons.keyboard
                    : Icons.add_reaction_outlined,
                key: ValueKey(controller.threadShowEmojiPicker),
              ),
            ),
            onPressed: controller.threadEmojiPickerAction,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: InputBar(
              room: controller.room,
              minLines: 1,
              maxLines: 8,
              autofocus: false,
              keyboardType: TextInputType.multiline,
              textInputAction:
                  AppSettings.sendOnEnter.value == true && PlatformInfos.isMobile
                      ? TextInputAction.send
                      : null,
              onSubmitted: controller.onThreadInputBarSubmitted,
              focusNode: controller.threadInputFocus,
              controller: controller.threadSendController,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.only(
                  left: 6.0,
                  right: 6.0,
                  bottom: 6.0,
                  top: 3.0,
                ),
                counter: const SizedBox.shrink(),
                hintText: L10n.of(context).writeAMessage,
                hintMaxLines: 1,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                filled: false,
              ),
              onChanged: controller.onThreadInputBarChanged,
              suggestionEmojis: getDefaultEmojiLocale(
                AppSettings.emojiSuggestionLocale.value.isNotEmpty
                    ? Locale(AppSettings.emojiSuggestionLocale.value)
                    : Localizations.localeOf(context),
              ).fold(
                [],
                (emojis, category) => emojis..addAll(category.emoji),
              ),
            ),
          ),
        ),
        Container(
          height: 56,
          width: 56,
          alignment: Alignment.center,
          child: IconButton(
            tooltip: L10n.of(context).send,
            onPressed: controller.threadSend,
            style: IconButton.styleFrom(
              backgroundColor: theme.bubbleColor,
              foregroundColor: theme.onBubbleColor,
            ),
            icon: const Icon(Icons.send_outlined),
          ),
        ),
      ],
    );
  }
}

// ---------- Thread-specific emoji picker ----------

class _ThreadEmojiPicker extends StatelessWidget {
  final ChatController controller;
  const _ThreadEmojiPicker({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: controller.threadShowEmojiPicker
          ? MediaQuery.sizeOf(context).height / 2
          : 0,
      child: controller.threadShowEmojiPicker
          ? DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: L10n.of(context).emojis),
                      Tab(text: L10n.of(context).stickers),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        EmojiPicker(
                          onEmojiSelected: controller.onThreadEmojiSelected,
                          onBackspacePressed:
                              controller.threadEmojiPickerBackspace,
                          config: Config(
                            locale: Localizations.localeOf(context),
                            emojiViewConfig: EmojiViewConfig(
                              noRecents: const _NoRecent(),
                              backgroundColor:
                                  theme.colorScheme.onInverseSurface,
                            ),
                            bottomActionBarConfig: const BottomActionBarConfig(
                              enabled: false,
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              backspaceColor: theme.colorScheme.primary,
                              iconColor: theme.colorScheme.primary.withAlpha(
                                128,
                              ),
                              iconColorSelected: theme.colorScheme.primary,
                              indicatorColor: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.surface,
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor: Color.lerp(
                                theme.colorScheme.surface,
                                theme.colorScheme.primaryContainer,
                                0.75,
                              )!,
                              indicatorColor: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        StickerPickerDialog(
                          room: controller.room,
                          onSelected: (sticker) {
                            controller.room.sendEvent(
                              {
                                'body': sticker.body,
                                'info': sticker.info ?? {},
                                'url': sticker.url.toString(),
                              },
                              type: EventTypes.Sticker,
                              threadRootEventId: controller.activeThreadId,
                              threadLastEventId: controller.threadLastEventId,
                            );
                            controller.threadHideEmojiPicker();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class _NoRecent extends StatelessWidget {
  const _NoRecent();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          L10n.of(context).emoteKeyboardNoRecents,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
