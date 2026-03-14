import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// A full-screen dialog that shows an in-app webview for OIDC authentication.
/// Intercepts navigation to the callback URL scheme and returns the full URL.
class OidcWebviewDialog extends StatefulWidget {
  final String url;
  final String callbackScheme;

  const OidcWebviewDialog({
    super.key,
    required this.url,
    required this.callbackScheme,
  });

  /// Shows the dialog and returns the callback URL string, or null if cancelled.
  static Future<String?> show(
    BuildContext context, {
    required String url,
    required String callbackScheme,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OidcWebviewDialog(
        url: url,
        callbackScheme: callbackScheme,
      ),
    );
  }

  @override
  State<OidcWebviewDialog> createState() => _OidcWebviewDialogState();
}

class _OidcWebviewDialogState extends State<OidcWebviewDialog> {
  bool _isLoading = true;
  String _title = 'Sign In';
  bool _popped = false;

  void _popWithResult(String? result) {
    if (_popped) return;
    _popped = true;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _popWithResult(null),
          ),
        ),
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.url),
              ),
              initialSettings: InAppWebViewSettings(
                useShouldOverrideUrlLoading: true,
                javaScriptEnabled: true,
                // Clear cache for clean login experience
                clearCache: false,
                // Allow inline media playback
                allowsInlineMediaPlayback: true,
              ),
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final url = navigationAction.request.url;
                if (url != null &&
                    url.scheme == widget.callbackScheme) {
                  // This is the callback URL — extract it and close the dialog
                  _popWithResult(url.toString());
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onLoadStart: (controller, url) {
                if (mounted) {
                  setState(() => _isLoading = true);
                }
              },
              onLoadStop: (controller, url) async {
                if (mounted) {
                  final title = await controller.getTitle();
                  setState(() {
                    _isLoading = false;
                    if (title != null && title.isNotEmpty) {
                      _title = title;
                    }
                  });
                }
              },
              onReceivedError: (controller, request, error) {
                // Check if this is a callback URL that failed to load
                // (custom schemes will fail to load but we should have caught them above)
                final url = request.url;
                if (url.scheme == widget.callbackScheme) {
                  _popWithResult(url.toString());
                }
              },
              onReceivedServerTrustAuthRequest: (controller, challenge) async {
                // Trust self-signed certificates for local development (*.localhost)
                final host = challenge.protectionSpace.host;
                if (host.endsWith('.localhost') || host == 'localhost') {
                  return ServerTrustAuthResponse(
                    action: ServerTrustAuthResponseAction.PROCEED,
                  );
                }
                return ServerTrustAuthResponse(
                  action: ServerTrustAuthResponseAction.CANCEL,
                );
              },
            ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
