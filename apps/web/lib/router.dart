import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'app_services.dart';
import 'features/agent/presentation/kiu_builder_page.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/owner_admin_bridge.dart';
import 'features/products/presentation/admin_home_page.dart';
import 'features/storefront/presentation/storefront_page.dart';
import 'features/stores/presentation/admin_login_page.dart';
import 'features/stores/presentation/create_store_page.dart';
import 'features/stores/presentation/welcome_page.dart';

/// Hash-based URLs (default on Flutter Web): `/#/s/{slug}` works on any static host.
GoRouter buildRouter(AppServices services, {String initialLocation = '/'}) =>
    GoRouter(
      initialLocation: initialLocation,
      refreshListenable: Listenable.merge([services.session, services.auth]),
      redirect: (context, state) {
        final loc = state.matchedLocation;
        final signedIn = services.auth.currentUser != null;
        if (loc == '/kiu' && !signedIn) return '/entrar';
        if (loc == '/entrar' && signedIn) return '/kiu';
        if (loc == '/admin' && !services.session.isSignedIn) {
          return signedIn ? '/mi-tienda' : '/clave';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => WelcomePage(services: services),
        ),
        GoRoute(
          path: '/entrar',
          builder: (_, _) => LoginPage(services: services),
        ),
        GoRoute(
          path: '/kiu',
          builder: (_, _) => KiuBuilderPage(services: services),
        ),
        GoRoute(
          path: '/mi-tienda',
          builder: (_, _) => OwnerAdminBridge(services: services),
        ),
        // POC flows (kept): anonymous creation and the kp_ key login.
        GoRoute(
          path: '/crear',
          builder: (_, _) => CreateStorePage(services: services),
        ),
        GoRoute(
          path: '/clave',
          builder: (_, _) => AdminLoginPage(services: services),
        ),
        GoRoute(
          path: '/admin',
          builder: (_, _) => AdminHomePage(services: services),
        ),
        GoRoute(
          path: '/s/:slug',
          builder: (_, state) => StorefrontPage(
            key: ValueKey(state.pathParameters['slug']),
            services: services,
            slug: state.pathParameters['slug']!,
          ),
        ),
      ],
    );
