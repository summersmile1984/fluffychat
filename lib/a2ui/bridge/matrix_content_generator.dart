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
      String actionName = actionText;
      String surfaceId = 'default';
      Map<String, dynamic>? dataModel;
      try {
        final parsed = json.decode(actionText) as Map<String, dynamic>?;
        if (parsed != null && parsed.containsKey('userAction')) {
          final userAction = parsed['userAction'] as Map<String, dynamic>;
          actionName = userAction['name'] as String? ?? actionText;
          surfaceId = userAction['surfaceId'] as String? ?? 'default';
          // Pass action context as data model (contains resolved data bindings)
          final context = userAction['context'] as Map<String, dynamic>?;
          if (context != null && context.isNotEmpty) {
            dataModel = context;
          }
        }
      } catch (_) {
        // text isn't valid JSON, use as plain action name
      }
      _actionSender.sendAction(
        action: actionName,
        surfaceId: surfaceId,
        dataModel: dataModel,
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
