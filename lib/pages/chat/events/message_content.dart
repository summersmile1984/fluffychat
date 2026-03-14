import 'dart:math';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/poll.dart';
import 'package:fluffychat/pages/chat/events/video_player.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../../config/app_config.dart';
import '../../../utils/event_checkbox_extension.dart';
import '../../../utils/platform_infos.dart';
import '../../../utils/url_launcher.dart';
import 'audio_player.dart';
import 'cute_events.dart';
import 'html_message.dart';
import 'image_bubble.dart';
import 'map_bubble.dart';
import 'message_download_content.dart';
import 'url_preview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:fluffychat/a2ui/widgets/a2ui_message_bubble.dart';
import 'streaming_message_content.dart';

class MessageContent extends StatelessWidget {
  static final _urlRegex = RegExp(
    r'https?://[^\s<>\])"]+',
    caseSensitive: false,
  );

  final Event event;
  final Color textColor;
  final Color linkColor;
  final void Function(Event)? onInfoTab;
  final BorderRadius borderRadius;
  final Timeline timeline;
  final bool selected;

  const MessageContent(
    this.event, {
    this.onInfoTab,
    super.key,
    required this.timeline,
    required this.textColor,
    required this.linkColor,
    required this.borderRadius,
    required this.selected,
  });

  Future<void> _verifyOrRequestKey(BuildContext context) async {
    final l10n = L10n.of(context);
    if (event.content['can_request_session'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(event.calcLocalizedBodyFallback(MatrixLocals(l10n))),
        ),
      );
      return;
    }
    final client = Matrix.of(context).client;
    final state = await client.getCryptoIdentityState();
    if (!state.connected) {
      final success = await context.push('/backup');
      if (success != true) return;
    }
    event.requestKey();
    final sender = event.senderFromMemoryOrFallback;
    await showAdaptiveBottomSheet(
      context: context,
      builder: (context) => Scaffold(
        appBar: AppBar(
          leading: CloseButton(onPressed: Navigator.of(context).pop),
          title: Text(
            l10n.whyIsThisMessageEncrypted,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(
                  mxContent: sender.avatarUrl,
                  name: sender.calcDisplayname(),
                  presenceUserId: sender.stateKey,
                  client: event.room.client,
                ),
                title: Text(sender.calcDisplayname()),
                subtitle: Text(event.originServerTs.localizedTime(context)),
                trailing: const Icon(Icons.lock_outlined),
              ),
              const Divider(),
              Text(event.calcLocalizedBodyFallback(MatrixLocals(l10n))),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontSize =
        AppConfig.messageFontSize * AppSettings.fontSizeFactor.value;
    final buttonTextColor = textColor;
    switch (event.type) {
      case EventTypes.Message:
      case EventTypes.Encrypted:
      case EventTypes.Sticker:
        switch (event.messageType) {
          case MessageTypes.Image:
          case MessageTypes.Sticker:
            if (event.redacted) continue textmessage;
            final maxSize = event.messageType == MessageTypes.Sticker
                ? 128.0
                : 256.0;
            final w = event.content
                .tryGetMap<String, Object?>('info')
                ?.tryGet<int>('w');
            final h = event.content
                .tryGetMap<String, Object?>('info')
                ?.tryGet<int>('h');
            var width = maxSize;
            var height = maxSize;
            var fit = event.messageType == MessageTypes.Sticker
                ? BoxFit.contain
                : BoxFit.cover;
            if (w != null && h != null) {
              fit = BoxFit.contain;
              if (w > h) {
                width = maxSize;
                height = max(32, maxSize * (h / w));
              } else {
                height = maxSize;
                width = max(32, maxSize * (w / h));
              }
            }
            return ImageBubble(
              event,
              width: width,
              height: height,
              fit: fit,
              borderRadius: borderRadius,
              timeline: timeline,
              textColor: textColor,
              onTap: () => showDialog(
                context: context,
                builder: (_) => ImageViewer(
                  event,
                  timeline: timeline,
                  outerContext: context,
                ),
              ),
            );
          case CuteEventContent.eventType:
            return CuteContent(event);
          case MessageTypes.Audio:
            if (PlatformInfos.isMobile ||
                PlatformInfos.isMacOS ||
                PlatformInfos.isWeb
            // Disabled until https://github.com/bleonard252/just_audio_mpv/issues/3
            // is fixed
            //   || PlatformInfos.isLinux
            ) {
              return AudioPlayerWidget(
                event,
                color: textColor,
                linkColor: linkColor,
                fontSize: fontSize,
              );
            }
            return MessageDownloadContent(
              event,
              textColor: textColor,
              linkColor: linkColor,
            );
          case MessageTypes.Video:
            return EventVideoPlayer(
              event,
              textColor: textColor,
              linkColor: linkColor,
              timeline: timeline,
            );
          case MessageTypes.File:
            return MessageDownloadContent(
              event,
              textColor: textColor,
              linkColor: linkColor,
            );
          case MessageTypes.BadEncrypted:
          case EventTypes.Encrypted:
            return _ButtonContent(
              textColor: buttonTextColor,
              onPressed: () => _verifyOrRequestKey(context),
              icon: '🔒',
              label: L10n.of(context).encrypted,
              fontSize: fontSize,
            );
          case MessageTypes.Location:
            final geoUri = Uri.tryParse(
              event.content.tryGet<String>('geo_uri')!,
            );
            if (geoUri != null && geoUri.scheme == 'geo') {
              final latlong = geoUri.path
                  .split(';')
                  .first
                  .split(',')
                  .map(double.tryParse)
                  .toList();
              if (latlong.length == 2 &&
                  latlong.first != null &&
                  latlong.last != null) {
                return Column(
                  mainAxisSize: .min,
                  children: [
                    MapBubble(
                      latitude: latlong.first!,
                      longitude: latlong.last!,
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      icon: Icon(Icons.location_on_outlined, color: textColor),
                      onPressed: UrlLauncher(
                        context,
                        geoUri.toString(),
                      ).launchUrl,
                      label: Text(
                        L10n.of(context).openInMaps,
                        style: TextStyle(color: textColor),
                      ),
                    ),
                  ],
                );
              }
            }
            continue textmessage;
          case MessageTypes.Text:
          case MessageTypes.Notice:
          case MessageTypes.Emote:
          case MessageTypes.None:
          textmessage:
          default:
            if (event.redacted) {
              return RedactionWidget(
                event: event,
                buttonTextColor: buttonTextColor,
                onInfoTab: onInfoTab,
                fontSize: fontSize,
              );
            }
            // ── Format-based routing ──
            final format = event.content['format'] as String?;

            // 1. Streaming: real-time delta rendering (takes priority)
            if (event.content['streaming'] == true) {
              return StreamingMessageContent(
                event: event,
                timeline: timeline,
                textColor: textColor,
                linkColor: linkColor,
              );
            }

            // 2. A2UI: dynamic UI components
            if (format == 'org.matrix.custom.a2ui' ||
                event.content['a2ui_content'] != null) {
              return A2uiMessageBubble(
                event: event,
                textColor: textColor,
                linkColor: linkColor,
              );
            }

            // 3. Markdown: render body as markdown
            if (format == 'org.matrix.custom.markdown') {
              final urlMatch = _urlRegex.firstMatch(event.body);
              final previewUrl = urlMatch?.group(0);
              final showPreview = previewUrl != null;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MarkdownBody(
                      data: event.body,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                            color: textColor, fontSize: fontSize),
                        h1: TextStyle(
                          color: textColor,
                          fontSize: fontSize * 1.6,
                          fontWeight: FontWeight.bold,
                        ),
                        h2: TextStyle(
                          color: textColor,
                          fontSize: fontSize * 1.4,
                          fontWeight: FontWeight.bold,
                        ),
                        h3: TextStyle(
                          color: textColor,
                          fontSize: fontSize * 1.2,
                          fontWeight: FontWeight.bold,
                        ),
                        h4: TextStyle(
                          color: textColor,
                          fontSize: fontSize * 1.1,
                          fontWeight: FontWeight.bold,
                        ),
                        code: TextStyle(
                          color: textColor,
                          backgroundColor:
                              textColor.withAlpha(20),
                          fontSize: fontSize * 0.9,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: textColor.withAlpha(15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        a: TextStyle(
                          color: linkColor,
                          decoration: TextDecoration.underline,
                          decorationColor: linkColor,
                        ),
                        listBullet: TextStyle(
                            color: textColor, fontSize: fontSize),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                                color: textColor, width: 4),
                          ),
                        ),
                        blockquotePadding:
                            const EdgeInsets.only(left: 8),
                        tableBorder: TableBorder.all(
                          color: textColor.withAlpha(80),
                        ),
                      ),
                      onTapLink: (text, href, title) {
                        if (href != null) {
                          UrlLauncher(context, href).launchUrl();
                        }
                      },
                    ),
                    if (showPreview)
                      UrlPreviewWidget(
                        url: previewUrl,
                        client: event.room.client,
                      ),
                  ],
                ),
              );
            }

            // 4. HTML / plain text (original path)
            var html = AppSettings.renderHtml.value && event.isRichMessage
                ? event.formattedText
                : event.body.replaceAll('<', '&lt;').replaceAll('>', '&gt;');
            if (event.messageType == MessageTypes.Emote) {
              html = '* $html';
            }

            final bigEmotes =
                event.onlyEmotes &&
                event.numberEmotes > 0 &&
                event.numberEmotes <= 3;
            final urlMatch = _urlRegex.firstMatch(event.body);
            final previewUrl = urlMatch?.group(0);
            final showPreview = previewUrl != null;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  HtmlMessage(
                    html: html,
                    textColor: textColor,
                    room: event.room,
                    fontSize:
                        AppSettings.fontSizeFactor.value *
                        AppConfig.messageFontSize *
                        (bigEmotes ? 5 : 1),
                    limitHeight: !selected,
                    linkStyle: TextStyle(
                      color: linkColor,
                      fontSize:
                          AppSettings.fontSizeFactor.value *
                          AppConfig.messageFontSize,
                      decoration: TextDecoration.underline,
                      decorationColor: linkColor,
                    ),
                    onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                    eventId: event.eventId,
                    checkboxCheckedEvents: event.aggregatedEvents(
                      timeline,
                      EventCheckboxRoomExtension.relationshipType,
                    ),
                  ),
                  if (showPreview)
                    UrlPreviewWidget(
                      url: previewUrl,
                      client: event.room.client,
                    ),
                ],
              ),
            );
        }
      case PollEventContent.startType:
        if (event.redacted) {
          return RedactionWidget(
            event: event,
            buttonTextColor: buttonTextColor,
            onInfoTab: onInfoTab,
            fontSize: fontSize,
          );
        }
        return PollWidget(
          event: event,
          timeline: timeline,
          textColor: textColor,
          linkColor: linkColor,
        );
      case EventTypes.CallInvite:
        return FutureBuilder<User?>(
          future: event.fetchSenderUser(),
          builder: (context, snapshot) {
            return _ButtonContent(
              label: L10n.of(context).startedACall(
                snapshot.data?.calcDisplayname() ??
                    event.senderFromMemoryOrFallback.calcDisplayname(),
              ),
              icon: '📞',
              textColor: buttonTextColor,
              onPressed: () => onInfoTab!(event),
              fontSize: fontSize,
            );
          },
        );
      default:
        return FutureBuilder<User?>(
          future: event.fetchSenderUser(),
          builder: (context, snapshot) {
            return _ButtonContent(
              label: L10n.of(context).userSentUnknownEvent(
                snapshot.data?.calcDisplayname() ??
                    event.senderFromMemoryOrFallback.calcDisplayname(),
                event.type,
              ),
              icon: 'ℹ️',
              textColor: buttonTextColor,
              onPressed: () => onInfoTab!(event),
              fontSize: fontSize,
            );
          },
        );
    }
  }
}

class RedactionWidget extends StatelessWidget {
  const RedactionWidget({
    super.key,
    required this.event,
    required this.buttonTextColor,
    required this.onInfoTab,
    required this.fontSize,
  });

  final Event event;
  final Color buttonTextColor;
  final void Function(Event p1)? onInfoTab;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: event.redactedBecause?.fetchSenderUser(),
      builder: (context, snapshot) {
        final reason = event.redactedBecause?.content.tryGet<String>('reason');
        final redactedBy =
            snapshot.data?.calcDisplayname() ??
            event.redactedBecause?.senderId.localpart ??
            L10n.of(context).user;
        return _ButtonContent(
          label: reason == null
              ? L10n.of(context).redactedBy(redactedBy)
              : L10n.of(context).redactedByBecause(redactedBy, reason),
          icon: '🗑️',
          textColor: buttonTextColor.withAlpha(128),
          onPressed: () => onInfoTab!(event),
          fontSize: fontSize,
        );
      },
    );
  }
}

class _ButtonContent extends StatelessWidget {
  final void Function() onPressed;
  final String label;
  final String icon;
  final Color? textColor;
  final double fontSize;

  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.textColor,
    required this.onPressed,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onPressed,
        child: Text(
          '$icon  $label',
          style: TextStyle(color: textColor, fontSize: fontSize),
        ),
      ),
    );
  }
}
