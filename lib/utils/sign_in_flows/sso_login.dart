import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sign_in_flows/oidc_webview_dialog.dart';

Future<void> ssoLoginFlow(
  Client client,
  BuildContext context,
  bool signUp,
) async {
  Logs().i('Starting legacy SSO Flow...');
  final redirectUrl = kIsWeb
      ? Uri.parse(
          html.window.location.href,
        ).resolveUri(Uri(pathSegments: ['auth.html'])).toString()
      : (PlatformInfos.isMobile || PlatformInfos.isWeb || PlatformInfos.isMacOS)
      ? '${AppConfig.appOpenUrlScheme.toLowerCase()}://login'
      : 'http://localhost:3001//login';

  final url = client.homeserver!.replace(
    path: '/_matrix/client/v3/login/sso/redirect',
    queryParameters: {
      'redirectUrl': redirectUrl,
      'action': signUp ? 'register' : 'login',
    },
  );

  final urlScheme =
      (PlatformInfos.isMobile || PlatformInfos.isWeb || PlatformInfos.isMacOS)
      ? Uri.parse(redirectUrl).scheme
      : 'http://localhost:3001';

  // Use in-app WebView for native platforms (mobile + desktop),
  // system browser only for web
  final String? result;
  if (!kIsWeb && (PlatformInfos.isMobile || PlatformInfos.isDesktop)) {
    Logs().i('Opening SSO in-app WebView with scheme=$urlScheme...');
    result = await OidcWebviewDialog.show(
      context,
      url: url.toString(),
      callbackScheme: urlScheme,
    );
    Logs().i('SSO WebView returned: $result');
    if (result == null) {
      Logs().w('SSO login cancelled by user');
      return;
    }
  } else {
    result = await FlutterWebAuth2.authenticate(
      url: url.toString(),
      callbackUrlScheme: urlScheme,
    );
  }

  final token = Uri.parse(result).queryParameters['loginToken'];
  if (token?.isEmpty ?? false) return;

  await client.login(
    LoginType.mLoginToken,
    token: token,
    initialDeviceDisplayName: PlatformInfos.clientName,
  );
}
