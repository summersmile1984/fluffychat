import 'dart:async';
import 'dart:convert';

import 'package:genui/genui.dart';
import 'package:matrix/matrix.dart';

import 'a2ui_action_sender.dart';

/// Bridges Matrix protocol to GenUI's [A2uiMessageProcessor].
///
/// This adapter connects the Matrix message system to the GenUI framework,
/// allowing A2UI content from Matrix events to be rendered by GenUI,
/// and user interactions to be sent back via Matrix messages.
class MatrixContentGenerator {
  final Room room;
  late final A2uiActionSender _actionSender;
  late final A2uiMessageProcessor _processor;
  StreamSubscription<UserUiInteractionMessage>? _submitSub;

  MatrixContentGenerator({required this.room, required Catalog catalog}) {
    _actionSender = A2uiActionSender(room: room);
    _processor = A2uiMessageProcessor(catalogs: [catalog]);

    // Forward user UI interactions to the Agent Bot via Matrix
    _submitSub = _processor.onSubmit.listen((message) {
      final actionText = message.text;
      Map<String, dynamic>? parsedData;
      try {
        parsedData = json.decode(actionText) as Map<String, dynamic>?;
      } catch (_) {
        // text isn't valid JSON, use as plain action
      }
      // TODO(a2ui): GenUI's UserUiInteractionMessage (v0.7.0) does not expose
      // surfaceId. All interactions are sent as 'default'. When the library
      // adds surfaceId support, pass message.surfaceId here instead.
      _actionSender.sendAction(
        action: actionText,
        surfaceId: 'default',
        dataModel: parsedData,
      );
    });
  }

  /// The GenUI host that manages surfaces and handles rendering.
  A2uiMessageProcessor get processor => _processor;

  /// Feed raw A2UI messages into the processor.
  void processMessages(List<A2uiMessage> messages) {
    for (final message in messages) {
      _processor.handleMessage(message);
    }
  }

  /// Clean up resources.
  void dispose() {
    _submitSub?.cancel();
    _processor.dispose();
  }
}
