import 'package:matrix/matrix.dart';

/// Sends user interaction actions back to the Agent Bot via Matrix messages.
///
/// When a user interacts with an A2UI-rendered widget (e.g., clicks a button,
/// submits a form), this class packages the action and current DataModel
/// state into a Matrix message and sends it to the room.
class A2uiActionSender {
  final Room room;

  A2uiActionSender({required this.room});

  /// Send a user action back to the Agent Bot.
  ///
  /// [action] - The action name triggered by the user (e.g., "submit_form")
  /// [surfaceId] - The surface where the action occurred
  /// [dataModel] - Current state of all data-bound values in the surface
  Future<void> sendAction({
    required String action,
    required String surfaceId,
    Map<String, dynamic>? dataModel,
  }) async {
    final actionPayload = <String, dynamic>{
      'action': action,
      'surfaceId': surfaceId,
    };
    if (dataModel != null) {
      actionPayload['dataModel'] = dataModel;
    }
    await room.sendEvent({
      'msgtype': 'm.text',
      'body': '🎛️ [User tapped: $action]',
      'format': 'org.aotsea.a2ui_action',
      'a2ui_action': actionPayload,
    });
  }
}
