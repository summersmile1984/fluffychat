import 'dart:ui';

abstract class AppConfig {
  // Const and final configuration values (immutable)
  // @brand:primary_color
  static const Color primaryColor = Color(0xFF5625BA);
  // @brand:primary_color_light
  static const Color primaryColorLight = Color(0xFFCCBDEA);
  // @brand:secondary_color
  static const Color secondaryColor = Color(0xFF41a2bc);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  // @brand:deep_link_prefix
  static const String deepLinkPrefix = 'com.aotsea.im://chat/';
  static const String schemePrefix = 'matrix:';
  // @brand:push_channel_id
  static const String pushNotificationsChannelId = 'turning_agent_push';
  // @brand:push_app_id
  static const String pushNotificationsAppId = 'com.aotsea.im';
  static const double borderRadius = 18.0;
  static const double spaceBorderRadius = 11.0;
  static const double columnWidth = 360.0;

  // @brand:website
  static const String website = 'https://aotsea.com';
  // @brand:push_tutorial_url
  static const String enablePushTutorial = '';
  // @brand:encryption_tutorial_url
  static const String encryptionTutorial = '';
  // @brand:start_chat_tutorial_url
  static const String startChatTutorial = '';
  // @brand:stickers_tutorial_url
  static const String howDoIGetStickersTutorial = '';
  // @brand:app_id
  static const String appId = 'com.aotsea.im.TurningAgent';
  // @brand:app_open_url_scheme
  static const String appOpenUrlScheme = 'com.aotsea';

  // Pre-registered OIDC client_id. When set, skips dynamic client registration.
  // Register this client in the IDP with: public=true, PKCE=required, no secret.
  // @brand:oidc_client_id
  static const String oidcClientId = 'b7e2c4a1f9d83056e1a4c7b2d5f098a3';

  // @brand:source_code_url
  static const String sourceCodeUrl = '';
  // @brand:support_url
  static const String supportUrl = '';
  // @brand:changelog_url
  static const String changelogUrl = '';
  // @brand:donation_url
  static const String donationUrl = '';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  // @brand:new_issue_url
  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'aotsea.com',
    path: '/support',
  );

  // @brand:homeserver_list_url
  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'aotsea.com',
    path: '/homeservers.json',
  );

  // @brand:privacy_url
  static final Uri privacyUrl = Uri(
    scheme: 'https',
    host: 'aotsea.com',
    path: '/privacy',
  );

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
}
