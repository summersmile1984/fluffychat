import 'package:flutter/material.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import '../../../utils/url_launcher.dart';

/// Renders a message that is being streamed via delta edits.
///
/// Maintains a local buffer that appends delta content from each
/// m.replace edit event. When streaming finishes (streaming: false),
/// displays the final full text from the event body.
///
/// The accumulated text is treated as **Markdown** (which is the typical
/// format AI agents return) and rendered directly via [MarkdownBody].
class StreamingMessageContent extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  final Color textColor;
  final Color linkColor;

  const StreamingMessageContent({
    super.key,
    required this.event,
    required this.timeline,
    required this.textColor,
    required this.linkColor,
  });

  @override
  State<StreamingMessageContent> createState() =>
      _StreamingMessageContentState();
}

class _StreamingMessageContentState extends State<StreamingMessageContent>
    with SingleTickerProviderStateMixin {
  /// Accumulated text from delta edits (markdown format)
  String _streamBuffer = '';

  /// Track last processed event to avoid duplicate appends
  String? _lastProcessedEventId;

  /// Blinking cursor animation
  late AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _processEvent(widget.event);
  }

  @override
  void didUpdateWidget(StreamingMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Called when timeline updates trigger a rebuild with new displayEvent
    _processEvent(widget.event);
  }

  void _processEvent(Event event) {
    final eventId = event.eventId;
    if (eventId == _lastProcessedEventId) return;
    _lastProcessedEventId = eventId;

    final content = event.content;
    final isDelta = content['is_delta'] == true;
    final isStreaming = content['streaming'] == true;
    final body = event.body;

    if (isDelta && isStreaming) {
      // Append delta to buffer
      _streamBuffer += body;
    } else {
      // Full content (initial message or finish edit)
      _streamBuffer = body;
    }

    if (!isStreaming) {
      // Streaming finished, stop cursor animation
      _cursorController.stop();
    } else if (!_cursorController.isAnimating) {
      // Resume cursor if streaming is still active
      _cursorController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isStreaming = widget.event.content['streaming'] == true;
    final displayText =
        _streamBuffer.isEmpty ? widget.event.body : _streamBuffer;

    final fontSize =
        AppSettings.fontSizeFactor.value * AppConfig.messageFontSize;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Render markdown directly — no HTML intermediate step
          MarkdownBody(
            data: displayText,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: widget.textColor, fontSize: fontSize),
              h1: TextStyle(
                color: widget.textColor,
                fontSize: fontSize * 1.6,
                fontWeight: FontWeight.bold,
              ),
              h2: TextStyle(
                color: widget.textColor,
                fontSize: fontSize * 1.4,
                fontWeight: FontWeight.bold,
              ),
              h3: TextStyle(
                color: widget.textColor,
                fontSize: fontSize * 1.2,
                fontWeight: FontWeight.bold,
              ),
              code: TextStyle(
                color: widget.textColor,
                backgroundColor:
                    widget.textColor.withAlpha(20),
                fontSize: fontSize * 0.9,
              ),
              codeblockDecoration: BoxDecoration(
                color: widget.textColor.withAlpha(15),
                borderRadius: BorderRadius.circular(4),
              ),
              a: TextStyle(
                color: widget.linkColor,
                decoration: TextDecoration.underline,
                decorationColor: widget.linkColor,
              ),
              listBullet:
                  TextStyle(color: widget.textColor, fontSize: fontSize),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: widget.textColor, width: 4),
                ),
              ),
              blockquotePadding: const EdgeInsets.only(left: 8),
              tableBorder: TableBorder.all(
                color: widget.textColor.withAlpha(80),
              ),
            ),
            onTapLink: (text, href, title) {
              if (href != null) {
                UrlLauncher(context, href).launchUrl();
              }
            },
          ),
          if (isStreaming)
            FadeTransition(
              opacity: _cursorController,
              child: Text(
                '▌',
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: fontSize,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
