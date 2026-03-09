import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/pdf_thumbnail_browser.dart';
import 'package:fluffychat/pages/image_viewer/archive_viewer.dart';
import 'package:fluffychat/pages/image_viewer/office_doc_viewer.dart';
import 'package:fluffychat/pages/image_viewer/pdf_viewer.dart';
import 'package:fluffychat/pages/image_viewer/svg_viewer.dart';
import 'package:fluffychat/pages/image_viewer/text_file_viewer.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/url_launcher.dart';

class MessageDownloadContent extends StatelessWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;

  const MessageDownloadContent(
    this.event, {
    required this.textColor,
    required this.linkColor,
    super.key,
  });

  // ── Extension / MIME sets ──────────────────────────────────────────

  static const _officeExtensions = {
    'DOCX', 'PPTX', 'XLSX', 'DOC', 'PPT', 'XLS',
  };

  static const _officeMimes = {
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/msword',
    'application/vnd.ms-powerpoint',
    'application/vnd.ms-excel',
  };

  static const _textExtensions = {
    'TXT', 'MD', 'JSON', 'XML', 'YAML', 'YML', 'CSV', 'LOG',
    'SH', 'BAT', 'PY', 'JS', 'TS', 'DART', 'JAVA', 'C', 'CPP',
    'H', 'GO', 'RS', 'RB', 'PHP', 'HTML', 'CSS', 'SQL', 'TOML',
    'INI', 'CFG', 'CONF', 'ENV', 'PROPERTIES', 'TSX', 'JSX',
    'SWIFT', 'KT', 'R', 'LUA', 'PL', 'MAKEFILE', 'DOCKERFILE',
    'GITIGNORE', 'EDITORCONFIG', 'LOCK',
  };

  static const _archiveExtensions = {
    'ZIP', 'TAR', 'GZ', 'BZ2', 'XZ', '7Z', 'RAR',
    'TGZ', 'LZMA', 'ZSTD',
  };

  static const _archiveMimes = {
    'application/zip',
    'application/x-zip-compressed',
    'application/x-tar',
    'application/gzip',
    'application/x-gzip',
    'application/x-bzip2',
    'application/x-xz',
    'application/x-7z-compressed',
    'application/x-rar-compressed',
    'application/vnd.rar',
    'application/x-lzma',
    'application/zstd',
    'application/x-compressed-tar',
  };

  @override
  Widget build(BuildContext context) {
    final filename = event.content.tryGet<String>('filename') ?? event.body;
    final filetype = (filename.contains('.')
        ? filename.split('.').last.toUpperCase()
        : event.content
                  .tryGetMap<String, Object?>('info')
                  ?.tryGet<String>('mimetype')
                  ?.toUpperCase() ??
              'UNKNOWN');

    final mimetype = event.content
        .tryGetMap<String, Object?>('info')
        ?.tryGet<String>('mimetype')
        ?.toLowerCase();

    // ── Type detection ─────────────────────────────────────────────
    final isPdf = filetype == 'PDF' || mimetype == 'application/pdf';

    final isOfficeDoc = _officeExtensions.contains(filetype) ||
        _officeMimes.contains(mimetype);

    final isSvg = filetype == 'SVG' || mimetype == 'image/svg+xml';

    final isTextFile = _textExtensions.contains(filetype) ||
        (mimetype != null &&
            mimetype.startsWith('text/') &&
            mimetype != 'text/html');

    // Check for compound archive extensions like .tar.gz
    final lowerFilename = filename.toLowerCase();
    final isArchive = _archiveExtensions.contains(filetype) ||
        _archiveMimes.contains(mimetype) ||
        lowerFilename.endsWith('.tar.gz') ||
        lowerFilename.endsWith('.tar.bz2') ||
        lowerFilename.endsWith('.tar.xz') ||
        lowerFilename.endsWith('.tbz2') ||
        lowerFilename.endsWith('.txz');

    final hasPreview = isPdf || isOfficeDoc || isSvg || isTextFile || isArchive;
    final sizeString = event.sizeString ?? '?MB';
    final fileDescription = event.fileDescription;

    // ── Choose the icon ────────────────────────────────────────────
    final IconData typeIcon;
    if (isPdf) {
      typeIcon = Icons.picture_as_pdf_outlined;
    } else if (isOfficeDoc) {
      typeIcon = Icons.description_outlined;
    } else if (isSvg) {
      typeIcon = Icons.image_outlined;
    } else if (isTextFile) {
      typeIcon = Icons.code_outlined;
    } else if (isArchive) {
      typeIcon = Icons.folder_zip_outlined;
    } else {
      typeIcon = Icons.file_download_outlined;
    }

    // ── Choose the onTap handler ───────────────────────────────────
    VoidCallback onTap;
    if (isPdf) {
      onTap = () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PdfViewer(event, outerContext: context),
            ),
          );
    } else if (isOfficeDoc) {
      onTap = () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OfficeDocViewer(event, outerContext: context),
            ),
          );
    } else if (isSvg) {
      onTap = () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SvgViewer(event, outerContext: context),
            ),
          );
    } else if (isTextFile) {
      onTap = () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TextFileViewer(event, outerContext: context),
            ),
          );
    } else if (isArchive) {
      onTap = () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArchiveViewer(event, outerContext: context),
            ),
          );
    } else {
      onTap = () => event.saveFile(context);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(hasPreview ? 128 : 0),
          clipBehavior: Clip.hardEdge,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          child: InkWell(
            onTap: onTap,
            onLongPress: hasPreview ? () => event.saveFile(context) : null,
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isPdf)
                    PdfThumbnailBrowser(
                      event,
                      width: 400,
                      height: 250,
                      fit: BoxFit.cover,
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 16,
                      children: [
                        CircleAvatar(
                          backgroundColor: textColor.withAlpha(32),
                          child: Icon(typeIcon, color: textColor),
                        ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '$sizeString | $filetype',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: textColor, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (fileDescription != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Linkify(
              text: fileDescription,
              textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
              style: TextStyle(
                color: textColor,
                fontSize:
                    AppSettings.fontSizeFactor.value *
                    AppConfig.messageFontSize,
              ),
              options: const LinkifyOptions(humanize: false),
              linkStyle: TextStyle(
                color: linkColor,
                fontSize:
                    AppSettings.fontSizeFactor.value *
                    AppConfig.messageFontSize,
                decoration: TextDecoration.underline,
                decorationColor: linkColor,
              ),
              onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
            ),
          ),
        ],
      ],
    );
  }
}
