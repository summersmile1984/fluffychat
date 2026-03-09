import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:archive/archive.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';

class ArchiveViewer extends StatelessWidget {
  final Event event;
  final BuildContext outerContext;

  const ArchiveViewer(
    this.event, {
    required this.outerContext,
    super.key,
  });

  /// Attempt to decode the archive. Returns null if format is unsupported.
  static Archive? _decodeArchive(Uint8List bytes, String filename) {
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    // Handle double extensions like .tar.gz
    final lowerName = filename.toLowerCase();

    try {
      if (lowerName.endsWith('.tar.gz') || lowerName.endsWith('.tgz')) {
        final decompressed = GZipDecoder().decodeBytes(bytes);
        return TarDecoder().decodeBytes(decompressed);
      }
      if (lowerName.endsWith('.tar.bz2') || lowerName.endsWith('.tbz2')) {
        final decompressed = BZip2Decoder().decodeBytes(bytes);
        return TarDecoder().decodeBytes(decompressed);
      }
      if (lowerName.endsWith('.tar.xz') || lowerName.endsWith('.txz')) {
        final decompressed = XZDecoder().decodeBytes(bytes);
        return TarDecoder().decodeBytes(decompressed);
      }

      return switch (ext) {
        'zip' => ZipDecoder().decodeBytes(bytes),
        'tar' => TarDecoder().decodeBytes(bytes),
        'gz' || 'gzip' => _trySingleOrTar(GZipDecoder().decodeBytes(bytes)),
        'bz2' || 'bzip2' => _trySingleOrTar(BZip2Decoder().decodeBytes(bytes)),
        'xz' => _trySingleOrTar(XZDecoder().decodeBytes(bytes)),
        _ => ZipDecoder().decodeBytes(bytes), // fallback try zip
      };
    } catch (e) {
      Logs().w('Failed to decode archive', e);
      return null;
    }
  }

  /// Try to decode decompressed bytes as tar; if not tar, create a
  /// single-entry archive.
  static Archive _trySingleOrTar(List<int> decompressed) {
    try {
      return TarDecoder().decodeBytes(decompressed);
    } catch (_) {
      // Not a tar, just a single compressed file
      final archive = Archive();
      archive.addFile(
        ArchiveFile('(decompressed content)', decompressed.length,
            decompressed),
      );
      return archive;
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static IconData _iconForEntry(ArchiveFile entry) {
    if (entry.isFile) {
      final name = entry.name.toLowerCase();
      if (name.endsWith('.jpg') || name.endsWith('.jpeg') ||
          name.endsWith('.png') || name.endsWith('.gif') ||
          name.endsWith('.webp') || name.endsWith('.svg')) {
        return Icons.image_outlined;
      }
      if (name.endsWith('.mp4') || name.endsWith('.mov') ||
          name.endsWith('.avi') || name.endsWith('.mkv')) {
        return Icons.video_file_outlined;
      }
      if (name.endsWith('.mp3') || name.endsWith('.ogg') ||
          name.endsWith('.wav') || name.endsWith('.m4a')) {
        return Icons.audio_file_outlined;
      }
      if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
      if (name.endsWith('.zip') || name.endsWith('.tar') ||
          name.endsWith('.gz') || name.endsWith('.7z') ||
          name.endsWith('.rar')) {
        return Icons.folder_zip_outlined;
      }
      return Icons.insert_drive_file_outlined;
    }
    return Icons.folder_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final filename = event.content.tryGet<String>('filename') ?? event.body;
    final theme = Theme.of(context);

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
                style: TextStyle(color: theme.colorScheme.error),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          final archive = _decodeArchive(snapshot.data!.bytes, filename);
          if (archive == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [
                    Icon(
                      Icons.folder_zip_outlined,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    Text(
                      'Unable to read this archive format.\nYou can download the file to open it with an external app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => event.saveFile(context),
                      icon: const Icon(Icons.download_outlined),
                      label: Text(L10n.of(context).downloadFile),
                    ),
                  ],
                ),
              ),
            );
          }

          final files = archive.files.where((f) => f.isFile).toList();
          final totalSize = files.fold<int>(0, (sum, f) => sum + f.size);

          return Column(
            children: [
              // Summary header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
                child: Row(
                  spacing: 12,
                  children: [
                    Icon(
                      Icons.folder_zip_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    Expanded(
                      child: Text(
                        '${files.length} files · ${_formatSize(totalSize)}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // File list
              Expanded(
                child: ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = files[index];
                    return ListTile(
                      leading: Icon(
                        _iconForEntry(entry),
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: Text(
                        _formatSize(entry.size),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
