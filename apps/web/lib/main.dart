import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'app_services.dart';
import 'core/auth/auth_gateway.dart';
import 'core/auth/disabled_auth_gateway.dart';
import 'core/auth/emulator_auth_gateway.dart';
import 'core/auth/firebase_auth_gateway.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/platform/local_store.dart';
import 'core/platform/platform_actions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  await initLocalStore();
  final api = ApiClient(baseUrl: config.apiBaseUrl)
    ..uploadClientFactory = http.Client.new; // abortable uploads
  final services = AppServices(
    api: api,
    platform: PlatformActions.live(),
    publicBase: kIsWeb ? Uri.base : config.publicWebBase,
    auth: await _auth(config),
  );
  runApp(KiuPopApp(services: services));
}

/// Local: the Auth emulator over REST (no Google endpoints involved).
/// Otherwise: the KiuPop Firebase project through the official SDK.
Future<AuthGateway> _auth(AppConfig config) async {
  if (config.authEmulatorHost.isNotEmpty) {
    return EmulatorAuthGateway(
      host: config.authEmulatorHost,
      facebookEnabled: config.facebookAuthEnabled,
    );
  }
  try {
    final auth = await FirebaseAuthGateway.create(
      projectId: config.firebaseProjectId,
      apiKey: config.firebaseApiKey,
      appId: config.firebaseAppId,
      facebookEnabled: config.facebookAuthEnabled,
    );
    await auth.ready.timeout(const Duration(seconds: 4), onTimeout: () {});
    return auth;
  } on Object {
    return DisabledAuthGateway(); // the public catalog keeps working without auth
  }
}
