import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/pdf_thumbnail_browser.dart';
import 'package:fluffychat/pages/image_viewer/office_doc_viewer.dart';
import 'package:fluffychat/pages/image_viewer/pdf_viewer.dart';
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
    final isPdf = filetype == 'PDF' ||
        (event.content
                .tryGetMap<String, Object?>('info')
                ?.tryGet<String>('mimetype')
                ?.toLowerCase() ==
            'application/pdf');
    const officeExtensions = {'DOCX', 'PPTX', 'XLSX'};
    final mimetype = event.content
        .tryGetMap<String, Object?>('info')
        ?.tryGet<String>('mimetype')
        ?.toLowerCase();
    final isOfficeDoc = officeExtensions.contains(filetype) ||
        mimetype == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
        mimetype == 'application/vnd.openxmlformats-officedocument.presentationml.presentation' ||
        mimetype == 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    final hasPreview = isPdf || isOfficeDoc;
    final sizeString = event.sizeString ?? '?MB';
    final fileDescription = event.fileDescription;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(hasPreview ? 128 : 0),
          clipBehavior: Clip.hardEdge,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          child: InkWell(
            onTap: isPdf
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PdfViewer(event, outerContext: context),
                      ),
                    )
                : isOfficeDoc
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OfficeDocViewer(event, outerContext: context),
                          ),
                        )
                    : () => event.saveFile(context),
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
                      mainAxisSize: .min,
                      spacing: 16,
                      children: [
                        CircleAvatar(
                          backgroundColor: textColor.withAlpha(32),
                          child: Icon(Icons.file_download_outlined, color: textColor),
                        ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: .start,
                            mainAxisSize: .min,
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
