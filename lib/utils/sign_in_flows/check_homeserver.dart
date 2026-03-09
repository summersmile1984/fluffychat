import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sign_in_flows/oidc_login.dart';
import 'package:fluffychat/utils/sign_in_flows/sso_login.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

Future<void> connectToHomeserverFlow(
  PublicHomeserverData homeserverData,
  BuildContext context,
  void Function(AsyncSnapshot<bool>) setState,
  bool signUp,
) async {
  setState(AsyncSnapshot.waiting());
  try {
    final homeserverInput = homeserverData.name!;
    var homeserver = Uri.parse(homeserverInput);
    if (homeserver.scheme != 'http' && homeserver.scheme != 'https') {
      // Uri.parse('localhost:8787') incorrectly puts 'localhost' as scheme.
      // Treat the entire input as a host (with optional port) and construct properly.
      // Use HTTP for local/private network addresses, HTTPS for everything else.
      if (homeserverInput.startsWith('localhost') ||
          homeserverInput.startsWith('127.0.0.1') ||
          homeserverInput.startsWith('192.168.')) {
        homeserver = Uri.parse('http://$homeserverInput');
      } else {
        homeserver = Uri.parse('https://$homeserverInput');
      }
    }
    final l10n = L10n.of(context);
    final client = await Matrix.of(context).getLoginClient();

    List loginFlows;
    dynamic authMetadata;
    try {
      final result = await client.checkHomeserver(
        homeserver,
        fetchAuthMetadata: true,
      );
      (_, _, loginFlows, authMetadata) = result;
    } catch (_) {
      // Some homeservers don't support auth metadata (e.g. no OIDC),
      // causing the SDK to throw. Retry without fetchAuthMetadata.
      final result = await client.checkHomeserver(homeserver);
      (_, _, loginFlows, authMetadata) = result;
    }

    final regLink = homeserverData.regLink;
    final supportsSso = loginFlows.any((flow) => flow.type == 'm.login.sso');

    if ((kIsWeb || PlatformInfos.isLinux) &&
        (supportsSso || authMetadata != null || (signUp && regLink != null))) {
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: l10n.appWantsToUseForLogin(homeserverInput),
        message: l10n.appWantsToUseForLoginDescription,
        okLabel: l10n.continueText,
      );
      if (consent != OkCancelResult.ok) return;
    }

    if (authMetadata != null) {
      await oidcLoginFlow(client, context, signUp);
    } else if (supportsSso) {
      await ssoLoginFlow(client, context, signUp);
    } else {
      if (signUp && regLink != null) {
        await launchUrlString(regLink);
      }
      final currentUri =
          GoRouter.of(context).routeInformationProvider.value.uri;
      final currentPath = currentUri.path.endsWith('/')
          ? currentUri.path.substring(0, currentUri.path.length - 1)
          : currentUri.path;
      context.go('$currentPath/login', extra: client);
      setState(AsyncSnapshot.withData(ConnectionState.done, true));
      return;
    }

    if (context.mounted) {
      setState(AsyncSnapshot.withData(ConnectionState.done, true));
    }
  } catch (e, s) {
    setState(AsyncSnapshot.withError(ConnectionState.done, e, s));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          e.toLocalizedString(context, ExceptionContext.checkHomeserver),
        ),
      ),
    );
  }
}
