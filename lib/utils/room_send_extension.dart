import 'package:html_unescape/html_unescape.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/markdown.dart';

/// Extension on [Room] to send text events with Turning Agent capabilities.
///
/// Wraps the standard event-send flow, appending
/// `org.aotsea.capabilities` to every outgoing m.text message,
/// so the bridge knows this client supports A2UI + markdown rendering.
extension TurningAgentRoomExtension on Room {
  static const _capabilities = <String, dynamic>{
    'a2ui': true,
    'markdown': true,
    'streaming': true,
    'version': '1.0',
  };

  /// Send a text event with Turning Agent capabilities attached.
  ///
  /// Delegates to [Room.sendTextEvent] for all standard processing
  /// (markdown, mentions, commands, threads, replies) and then
  /// — because the SDK doesn't expose an `extraContent` param on
  /// sendTextEvent — we instead call [Room.sendEvent] directly,
  /// replicating the minimal content-building that the SDK does.
  ///
  /// If [parseCommands] is true **and** the text matches a known
  /// command, it falls through to the SDK's command handler (which
  /// doesn't go through this path anyway, since chat.dart already
  /// guards for unknown commands).
  Future<String?> sendTextWithCapabilities(
    String message, {
    Event? inReplyTo,
    String? editEventId,
    bool parseCommands = true,
    String? threadRootEventId,
    String? threadLastEventId,
  }) {
    // Let the SDK handle slash-commands natively (no capabilities needed).
    if (parseCommands &&
        message.startsWith('/') &&
        client.commands.keys.contains(
          RegExp(r'^\/(\w+)').firstMatch(message)?[1]?.toLowerCase(),
        )) {
      return sendTextEvent(
        message,
        inReplyTo: inReplyTo,
        editEventId: editEventId,
        parseCommands: true,
        threadRootEventId: threadRootEventId,
        threadLastEventId: threadLastEventId,
      );
    }

    // Build the event content, replicating what sendTextEvent does
    // but adding our custom field.
    final event = <String, dynamic>{
      'msgtype': MessageTypes.Text,
      'body': message,
      'org.aotsea.capabilities': _capabilities,
    };

    // ── Mentions ──
    var potentialMentions = message
        .split('@')
        .map(
          (text) => text.startsWith('[')
              ? '@${text.split(']').first}]'
              : '@${text.split(RegExp(r'\s+')).first}',
        )
        .toList()
      ..removeAt(0);

    final hasRoomMention = potentialMentions.remove('@room');

    potentialMentions = potentialMentions
        .map(
          (mention) =>
              mention.isValidMatrixId ? mention : getMention(mention),
        )
        .nonNulls
        .toSet()
        .toList()
      ..remove(client.userID);

    if (inReplyTo != null) potentialMentions.add(inReplyTo.senderId);

    if (hasRoomMention || potentialMentions.isNotEmpty) {
      event['m.mentions'] = {
        if (hasRoomMention) 'room': true,
        if (potentialMentions.isNotEmpty) 'user_ids': potentialMentions,
      };
    }

    // ── Markdown ──
    final html = markdown(
      event['body'],
      getEmotePacks: () => getImagePacksFlat(ImagePackUsage.emoticon),
      getMention: getMention,
      convertLinebreaks: client.convertLinebreaksInFormatting,
    );
    if (HtmlUnescape().convert(html.replaceAll(RegExp(r'<br />\n?'), '\n')) !=
        event['body']) {
      event['format'] = 'org.matrix.custom.html';
      event['formatted_body'] = html;
    }

    return sendEvent(
      event,
      inReplyTo: inReplyTo,
      editEventId: editEventId,
      threadRootEventId: threadRootEventId,
      threadLastEventId: threadLastEventId,
    );
  }
}
