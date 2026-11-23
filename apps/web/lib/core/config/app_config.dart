/// Build-time configuration. Values come from `--dart-define`, never from
/// files shipped to the browser, so nothing secret can end up in the bundle.
/// (Firebase web API keys are public project identifiers, not secrets.)
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.firebaseProjectId,
    required this.firebaseApiKey,
    required this.firebaseAppId,
    required this.authEmulatorHost,
    required this.facebookAuthEnabled,
    required this.publicWebBase,
  });

  factory AppConfig.fromEnvironment() {
    const raw = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    );
    return AppConfig(
      apiBaseUrl: Uri.parse(raw),
      firebaseProjectId: const String.fromEnvironment(
        'FIREBASE_PROJECT_ID',
        defaultValue: 'demo-kiupop',
      ),
      firebaseApiKey: const String.fromEnvironment(
        'FIREBASE_API_KEY',
        defaultValue: 'demo-kiupop-local-key',
      ),
      firebaseAppId: const String.fromEnvironment(
        'FIREBASE_APP_ID',
        defaultValue: '1:000000000000:web:0000000000000000',
      ),
      authEmulatorHost: const String.fromEnvironment(
        'AUTH_EMULATOR_HOST',
        defaultValue: '',
      ),
      facebookAuthEnabled: const bool.fromEnvironment('FACEBOOK_AUTH_ENABLED'),
      publicWebBase: Uri.parse(
        const String.fromEnvironment(
          'PUBLIC_WEB_BASE',
          defaultValue: 'http://localhost:3000',
        ),
      ),
    );
  }

  final Uri apiBaseUrl;
  final String firebaseProjectId,
      firebaseApiKey,
      firebaseAppId,
      authEmulatorHost;
  final bool facebookAuthEnabled;

  /// Where the web catalog is served; the Android app builds share links from it
  /// (on web the page's own origin is used).
  final Uri publicWebBase;
}
