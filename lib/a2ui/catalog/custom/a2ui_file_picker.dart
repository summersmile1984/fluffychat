// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'package:genui/genui.dart';
import 'package:share_plus/share_plus.dart';

/// A2UI FilePicker — allows Agent to present a file sharing/selection UI.
///
/// The Agent can trigger file sharing via the system share sheet,
/// or present a download/open action for a given file URL.

final _fileSchema = S.object(
  properties: {
    'fileName': A2uiSchemas.stringReference(description: 'Display file name'),
    'fileUrl': S.string(description: 'URL of the file'),
    'fileSize': A2uiSchemas.stringReference(
        description: 'Human-readable file size'),
    'mimeType': S.string(description: 'MIME type'),
    'action': A2uiSchemas.action(),
  },
  required: ['fileName', 'fileUrl', 'action'],
);

class A2uiFilePicker {
  static final CatalogItem item = CatalogItem(
    name: 'FilePicker',
    dataSchema: _fileSchema,
    widgetBuilder: (itemContext) {
      final data = itemContext.data as JsonMap;
      final fileNameMap = data['fileName'] as Map;
      final fileName = fileNameMap['literalString'] as String? ?? 'File';
      final fileUrl = data['fileUrl'] as String;
      final fileSizeMap = data['fileSize'] as Map?;
      final fileSize = fileSizeMap?['literalString'] as String? ?? '';
      final mimeType = data['mimeType'] as String? ?? '';
      final actionData = data['action'] as JsonMap;

      IconData fileIcon;
      if (mimeType.startsWith('image/')) {
        fileIcon = Icons.image;
      } else if (mimeType.startsWith('video/')) {
        fileIcon = Icons.videocam;
      } else if (mimeType.startsWith('audio/')) {
        fileIcon = Icons.audiotrack;
      } else if (mimeType.contains('pdf')) {
        fileIcon = Icons.picture_as_pdf;
      } else {
        fileIcon = Icons.insert_drive_file;
      }

      return Card(
        child: ListTile(
          leading: Icon(fileIcon, size: 36),
          title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: fileSize.isNotEmpty ? Text(fileSize) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () {
                  SharePlus.instance.share(ShareParams(uri: Uri.parse(fileUrl)));
                },
              ),
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: () {
                  itemContext.dispatchEvent(
                    UserActionEvent(
                      name: actionData['name'] as String,
                      sourceComponentId: itemContext.id,
                      context: {'fileUrl': fileUrl, 'fileName': fileName},
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}
