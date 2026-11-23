import 'core/auth/auth_gateway.dart';
import 'core/network/api_client.dart';
import 'core/platform/platform_actions.dart';
import 'core/theme/theme_controller.dart';
import 'features/agent/data/agent_api.dart';
import 'features/catalog/data/catalog_api.dart';
import 'features/funnel/funnel_api.dart';
import 'features/products/data/products_api.dart';
import 'features/session/admin_session.dart';
import 'features/storefront/data/storefront_api.dart';
import 'features/stores/data/stores_api.dart';
import 'features/voice/data/speech_api.dart';
import 'features/voice/data/voice_io.dart';

/// Everything the UI depends on, built once in main() (constructor injection).
class AppServices {
  AppServices({
    required ApiClient api,
    required this.platform,
    required this.publicBase,
    required this.auth,
    AdminSession? session,
    ThemeController? theme,
    VoiceIO? voice,
  }) : stores = StoresApi(api),
       products = ProductsApi(api),
       catalog = CatalogApi(api),
       storefront = StorefrontApi(api),
       agent = AgentApi(api, auth),
       speech = SpeechApi(api, auth),
       funnel = FunnelApi(api, auth),
       voice = voice ?? VoiceIO.live(),
       session = session ?? AdminSession(),
       theme = theme ?? ThemeController();

  final StoresApi stores;
  final ProductsApi products;
  final CatalogApi catalog;
  final StorefrontApi storefront;
  final AgentApi agent;
  final SpeechApi speech;
  final FunnelApi funnel;

  /// Microphone and playback for voice notes (fakes in widget tests).
  final VoiceIO voice;
  final AuthGateway auth;
  final AdminSession session;
  final PlatformActions platform;
  final ThemeController theme;

  /// Origin where the web app is served (for shareable links).
  final Uri publicBase;

  /// Public catalog link. Hash routing keeps deep links working on any static host.
  Uri storeLink(String slug) =>
      publicBase.replace(path: '/', fragment: '/s/$slug');
}
