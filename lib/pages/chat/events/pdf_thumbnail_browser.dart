import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:pdf_render/pdf_render.dart';

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
  Uint8List? _thumbnailBytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPdfThumbnail();
  }

  Future<void> _loadPdfThumbnail() async {
    PdfDocument? doc;
    try {
      final file = await widget.event.downloadAndDecryptAttachment();
      doc = await PdfDocument.openData(file.bytes);
      if (doc.pageCount > 0) {
        final page = await doc.getPage(1);
        final pageImage = await page.render(
          width: (widget.width * 2).toInt(),
          height: (widget.height * 2).toInt(),
        );
        // Create the dart:ui Image and convert to PNG bytes
        final image = await pageImage.createImageIfNotAvailable();
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          _thumbnailBytes = byteData.buffer.asUint8List();
        }
        pageImage.dispose();
      }
    } catch (e) {
      Logs().w('Failed to load PDF thumbnail', e);
    } finally {
      doc?.dispose();
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

    if (_thumbnailBytes == null) {
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
      child: Image.memory(
        _thumbnailBytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
      ),
    );
  }
}
