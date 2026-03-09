abstract class Users {
  const Users._();

  static const user1 = User(
    String.fromEnvironment(
      'USER1_NAME',
      defaultValue: 'alice',
    ),
    String.fromEnvironment(
      'USER1_PW',
      defaultValue: 'AliceInWonderland',
    ),
  );
  static const user2 = User(
    String.fromEnvironment(
      'USER2_NAME',
      defaultValue: 'bob',
    ),
    String.fromEnvironment(
      'USER2_PW',
      defaultValue: 'JoWirSchaffenDas',
    ),
  );
}

class User {
  final String name;
  final String password;

  const User(this.name, this.password);
}

const homeserver = 'http://${String.fromEnvironment(
  'HOMESERVER',
  defaultValue: 'localhost',
)}';

/// Domain for constructing Matrix user IDs (e.g. localhost:8787)
const domain = String.fromEnvironment(
  'DOMAIN',
  defaultValue: 'localhost:8787',
);

/// Comma-separated bot localparts to test in E2E message tests
const _botLocalpartsRaw = String.fromEnvironment(
  'E2E_BOT_LOCALPARTS',
  defaultValue: 'research',
);

/// Parsed list of bot localparts
List<String> get botLocalparts =>
    _botLocalpartsRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

/// Get the full Matrix user ID for a bot localpart
String botMxid(String localpart) => '@$localpart:$domain';
