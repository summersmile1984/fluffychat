import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';

class SvgViewer extends StatelessWidget {
  final Event event;
  final BuildContext outerContext;

  const SvgViewer(
    this.event, {
    required this.outerContext,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final filename = event.content.tryGet<String>('filename') ?? event.body;
    return Scaffold(
      appBar: AppBar(
        title: Text(filename),
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
          return InteractiveViewer(
            maxScale: 10,
            child: Center(
              child: SvgPicture.memory(
                snapshot.data!.bytes,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}
