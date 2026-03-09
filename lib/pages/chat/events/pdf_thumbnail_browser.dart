import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class PdfThumbnailBrowser extends StatefulWidget {
  final Event event;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius borderRadius;

  const PdfThumbnailBrowser(
    this.event, {
    this.width = 400,
    this.height = 300,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    super.key,
  });

  @override
  State<PdfThumbnailBrowser> createState() => _PdfThumbnailBrowserState();
}

class _PdfThumbnailBrowserState extends State<PdfThumbnailBrowser> {
  Uint8List? _pdfBytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final file = await widget.event.downloadAndDecryptAttachment();
      _pdfBytes = file.bytes;
    } catch (e) {
      Logs().w('Failed to load PDF', e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }

    if (_pdfBytes == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Center(
          child: Icon(
            Icons.picture_as_pdf_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: IgnorePointer(
          child: SfPdfViewer.memory(
            _pdfBytes!,
            canShowScrollHead: false,
            canShowScrollStatus: false,
            enableDoubleTapZooming: false,
            enableTextSelection: false,
            canShowPaginationDialog: false,
            pageLayoutMode: PdfPageLayoutMode.single,
            scrollDirection: PdfScrollDirection.horizontal,
          ),
        ),
      ),
    );
  }
}
