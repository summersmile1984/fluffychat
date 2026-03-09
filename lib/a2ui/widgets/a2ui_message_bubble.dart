import 'package:flutter/material.dart';

import 'package:genui/genui.dart';
import 'package:matrix/matrix.dart';

import '../bridge/a2ui_event_parser.dart';
import '../bridge/matrix_content_generator.dart';
import '../catalog/catalog_registry.dart';

/// A2UI Message Bubble widget.
///
/// Renders dynamic A2UI content within a chat message bubble.
/// This is the single entry point for A2UI rendering in the chat timeline.
///
/// It parses A2UI messages from a Matrix event, feeds them into a
/// [MatrixContentGenerator] → [A2uiMessageProcessor] pipeline, and
/// renders the result using GenUI's [GenUiSurface].
class A2uiMessageBubble extends StatefulWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;

  const A2uiMessageBubble({
    required this.event,
    required this.textColor,
    required this.linkColor,
    super.key,
  });

  @override
  State<A2uiMessageBubble> createState() => _A2uiMessageBubbleState();
}

class _A2uiMessageBubbleState extends State<A2uiMessageBubble> {
  late MatrixContentGenerator _generator;
  late List<A2uiMessage> _messages;
  final Set<String> _surfaceIds = {};

  @override
  void initState() {
    super.initState();
    _initGenerator();
  }

  @override
  void didUpdateWidget(A2uiMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.eventId != widget.event.eventId) {
      _generator.dispose();
      _surfaceIds.clear();
      _initGenerator();
    }
  }

  void _initGenerator() {
    _generator = MatrixContentGenerator(
      room: widget.event.room,
      catalog: A2uiCatalogRegistry.catalog,
    );

    // Parse and process A2UI messages from the event
    _messages = A2uiEventParser.parseMessages(widget.event);
    _generator.processMessages(_messages);

    // Collect surface IDs for rendering
    for (final message in _messages) {
      switch (message) {
        case SurfaceUpdate():
          _surfaceIds.add(message.surfaceId);
        case BeginRendering():
          _surfaceIds.add(message.surfaceId);
        case DataModelUpdate():
          _surfaceIds.add(message.surfaceId);
        case SurfaceDeletion():
          _surfaceIds.remove(message.surfaceId);
      }
    }
  }

  @override
  void dispose() {
    _generator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_messages.isEmpty || _surfaceIds.isEmpty) {
      // Fallback: show plain text body if A2UI parsing fails
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          widget.event.body,
          style: TextStyle(color: widget.textColor),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Optional text body above the A2UI content
          if (widget.event.body.isNotEmpty &&
              !widget.event.body.startsWith('[')) ...[
            Text(
              widget.event.body,
              style: TextStyle(color: widget.textColor),
            ),
            const SizedBox(height: 8),
          ],
          // GenUI surface(s) for each A2UI surface
          ..._surfaceIds.map(
            (surfaceId) => GenUiSurface(
              host: _generator.processor,
              surfaceId: surfaceId,
              defaultBuilder: (_) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
