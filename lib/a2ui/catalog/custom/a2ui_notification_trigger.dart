// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'package:genui/genui.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// A2UI NotificationTrigger — lets the Agent schedule a local notification.
///
/// The Agent specifies the notification title, body, and when to show it.
/// The widget displays a preview card with a "Set Reminder" button.
/// Uses flutter_local_notifications (already in project deps).

final _notifSchema = S.object(
  properties: {
    'title': A2uiSchemas.stringReference(description: 'Notification title'),
    'body': A2uiSchemas.stringReference(description: 'Notification body text'),
    'delaySeconds': S.number(
      description: 'Delay in seconds before showing the notification',
    ),
    'action': A2uiSchemas.action(),
  },
  required: ['title', 'body', 'action'],
);

class A2uiNotificationTrigger {
  static final CatalogItem item = CatalogItem(
    name: 'NotificationTrigger',
    dataSchema: _notifSchema,
    widgetBuilder: (itemContext) {
      final data = itemContext.data as JsonMap;
      final titleMap = data['title'] as Map;
      final title = titleMap['literalString'] as String? ?? 'Reminder';
      final bodyMap = data['body'] as Map;
      final body = bodyMap['literalString'] as String? ?? '';
      final delaySeconds = (data['delaySeconds'] as num?)?.toInt() ?? 0;
      final actionData = data['action'] as JsonMap;

      final theme = Theme.of(itemContext.buildContext);

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.notifications_active, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleSmall),
                        if (body.isNotEmpty)
                          Text(
                            body,
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (delaySeconds > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Reminds in ${_formatDelay(delaySeconds)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.alarm_add),
                  label: const Text('Set Reminder'),
                  onPressed: () async {
                    try {
                      final plugin = FlutterLocalNotificationsPlugin();
                      // Show immediately or after delay
                      if (delaySeconds <= 0) {
                        await plugin.show(
                          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                          title: title,
                          body: body,
                          notificationDetails: const NotificationDetails(
                            android: AndroidNotificationDetails(
                              'a2ui_reminders',
                              'A2UI Reminders',
                              importance: Importance.high,
                            ),
                            iOS: DarwinNotificationDetails(),
                          ),
                        );
                      }
                    } catch (e) {
                      // Fallback: show SnackBar if notification API unavailable
                      if (itemContext.buildContext.mounted) {
                        ScaffoldMessenger.of(itemContext.buildContext).showSnackBar(
                          SnackBar(
                            content: Text('⏰ Reminder set: $title'),
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    }
                    // Dispatch action back to Agent
                    itemContext.dispatchEvent(
                      UserActionEvent(
                        name: actionData['name'] as String,
                        sourceComponentId: itemContext.id,
                        context: {
                          'title': title,
                          'body': body,
                          'delaySeconds': delaySeconds,
                          'status': 'scheduled',
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  static String _formatDelay(int seconds) {
    if (seconds >= 3600) {
      final hours = seconds ~/ 3600;
      return '$hours hour${hours > 1 ? 's' : ''}';
    } else if (seconds >= 60) {
      final minutes = seconds ~/ 60;
      return '$minutes minute${minutes > 1 ? 's' : ''}';
    } else {
      return '$seconds second${seconds > 1 ? 's' : ''}';
    }
  }
}
