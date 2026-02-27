import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';

class PdfViewer extends StatefulWidget {
  final Event event;
  final BuildContext outerContext;

  const PdfViewer(
    this.event, {
    required this.outerContext,
    super.key,
  });

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event.content.tryGet<String>('filename') ??
            widget.event.body),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => widget.event.shareFile(context),
            tooltip: L10n.of(context).share,
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => widget.event.saveFile(context),
            tooltip: L10n.of(context).downloadFile,
          ),
        ],
      ),
      body: FutureBuilder<MatrixFile>(
        future: widget.event.downloadAndDecryptAttachment(),
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
          return SfPdfViewer.memory(
            snapshot.data!.bytes,
            key: _pdfViewerKey,
            canShowScrollHead: false,
            canShowScrollStatus: false,
          );
        },
      ),
    );
  }
}
