

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/mxc_image.dart';

/// Cached URL preview metadata (lightweight, no image binary).
class _UrlPreviewData {
  final String? title;
  final String? description;
  final Uri? imageUri;
  final String? siteName;

  const _UrlPreviewData({
    this.title,
    this.description,
    this.imageUri,
    this.siteName,
  });

  bool get isEmpty =>
      (title == null || title!.isEmpty) &&
      (description == null || description!.isEmpty) &&
      imageUri == null;
}

class UrlPreviewWidget extends StatefulWidget {
  final String url;
  final Client client;

  const UrlPreviewWidget({
    required this.url,
    required this.client,
    super.key,
  });

  @override
  State<UrlPreviewWidget> createState() => _UrlPreviewWidgetState();
}

class _UrlPreviewWidgetState extends State<UrlPreviewWidget> {
  /// Cache preview metadata by URL. Only text data, no image bytes.
  static final Map<String, _UrlPreviewData?> _cache = {};

  _UrlPreviewData? _previewData;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final url = widget.url;

    // Check cache first
    if (_cache.containsKey(url)) {
      if (mounted) {
        setState(() {
          _previewData = _cache[url];
          _loaded = true;
        });
      }
      return;
    }

    try {
      final client = widget.client;
      Logs().w('[UrlPreview] Fetching preview for: $url');

      // Use the SDK's built-in request() which handles auth, base URI
      // and returns the raw JSON map — includes all og: fields.
      // Note: request() prepends '_matrix' to the path automatically.
      final json = await client.request(
        RequestType.GET,
        '/client/v1/media/preview_url',
        query: {'url': url},
      );

      Logs().w('[UrlPreview] Response for $url: $json');

      final ogImageRaw = json['og:image'];
      Uri? imageUri;
      if (ogImageRaw is String && ogImageRaw.isNotEmpty) {
        imageUri = Uri.tryParse(ogImageRaw);
      }

      final data = _UrlPreviewData(
        title: json['og:title'] as String?,
        description: json['og:description'] as String?,
        imageUri: imageUri,
        siteName: json['og:site_name'] as String?,
      );

      _cache[url] = data;

      if (mounted) {
        setState(() {
          _previewData = data;
          _loaded = true;
        });
      }
    } catch (e, s) {
      Logs().w('[UrlPreview] Failed for $url', e, s);
      _cache[url] = null;
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _previewData == null || _previewData!.isEmpty) {
      return const SizedBox.shrink();
    }

    final data = _previewData!;
    final theme = Theme.of(context);
    final domain = Uri.tryParse(widget.url)?.host ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: () => UrlLauncher(context, widget.url).launchUrl(),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thumbnail image
              if (data.imageUri != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 160,
                    minWidth: double.infinity,
                  ),
                  child: MxcImage(
                    uri: data.imageUri,
                    client: widget.client,
                    fit: BoxFit.cover,
                    width: 400,
                    height: 160,
                    isThumbnail: true,
                    placeholder: (_) => Container(
                      height: 160,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.image_outlined, size: 32),
                      ),
                    ),
                  ),
                ),
              // Text content
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Site name / domain
                    Text(
                      data.siteName ?? domain,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Title
                    if (data.title != null && data.title!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // Description
                    if (data.description != null &&
                        data.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
