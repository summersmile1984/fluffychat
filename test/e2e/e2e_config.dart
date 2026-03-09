/// E2E test configuration sourced from --dart-define environment variables.
///
/// Usage:
///   flutter test test/e2e/ \
///     --dart-define=E2E_HOMESERVER=http://localhost:8787 \
///     --dart-define=E2E_USER=admin \
///     --dart-define=E2E_PASSWORD=admin123 \
///     --dart-define=E2E_DOMAIN=localhost:8787 \
///     --dart-define=E2E_BOT_LOCALPARTS=research,hr,pm
class E2eConfig {
  /// Matrix homeserver URL (e.g. http://localhost:8787)
  static const homeserverUrl = String.fromEnvironment(
    'E2E_HOMESERVER',
    defaultValue: 'http://localhost:8787',
  );

  /// Login username (without @ prefix or :domain suffix)
  static const username = String.fromEnvironment(
    'E2E_USER',
    defaultValue: 'admin',
  );

  /// Login password
  static const password = String.fromEnvironment(
    'E2E_PASSWORD',
    defaultValue: 'admin123',
  );

  /// Homeserver domain (e.g. localhost:8787)
  static const domain = String.fromEnvironment(
    'E2E_DOMAIN',
    defaultValue: 'localhost:8787',
  );

  /// Comma-separated bot localparts to test (e.g. research,hr,pm)
  static const _botLocalpartsRaw = String.fromEnvironment(
    'E2E_BOT_LOCALPARTS',
    defaultValue: 'research',
  );

  /// Parsed list of bot localparts
  static List<String> get botLocalparts =>
      _botLocalpartsRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// Get the full Matrix user ID for a bot localpart
  static String botMxid(String localpart) => '@$localpart:$domain';

  /// Reply timeout for waiting for bot responses
  static const replyTimeoutMs = 90000;

  /// Settle delay: wait this long after last event before resolving
  static const settleDelayMs = 8000;
}
