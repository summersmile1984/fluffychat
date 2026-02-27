import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:microsoft_viewer/microsoft_viewer.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';

class OfficeDocViewer extends StatelessWidget {
  final Event event;
  final BuildContext outerContext;

  const OfficeDocViewer(
    this.event, {
    required this.outerContext,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          event.content.tryGet<String>('filename') ?? event.body,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => event.shareFile(context),
            tooltip: L10n.of(context).share,
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => event.saveFile(context),
            tooltip: L10n.of(context).downloadFile,
          ),
        ],
      ),
      body: FutureBuilder<MatrixFile>(
        future: event.downloadAndDecryptAttachment(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                L10n.of(context).oopsSomethingWentWrong,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return MicrosoftViewer(snapshot.data!.bytes, false);
        },
      ),
    );
  }
}
