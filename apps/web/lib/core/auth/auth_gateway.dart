import 'dart:async';

import 'package:flutter/foundation.dart';

/// The signed-in KiuPop user (identity comes from the KiuPop-dedicated
/// provider; the backend re-verifies every token and never trusts this object).
class AuthUser {
  const AuthUser({required this.uid, required this.email, this.name});
  final String uid;
  final String email;
  final String? name;
}

/// Why a sign-in failed, mapped to friendly copy in the UI.
enum AuthFailure {
  invalidCredentials,
  emailInUse,
  weakPassword,
  invalidEmail,
  popupClosed,
  providerDisabled,
  network,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.failure);
  final AuthFailure failure;
}

/// Sign-in port. [FirebaseAuthGateway] in the app, a fake in widget tests.
abstract class AuthGateway extends ChangeNotifier {
  AuthUser? get currentUser;

  /// "emulator" (local, test accounts) | "firebase" | "disabled".
  String get mode;

  bool get googleEnabled;

  /// Facebook stays off until the Meta app and test credentials exist.
  bool get facebookEnabled;

  /// A fresh ID token for the API (refreshed by the SDK when close to expiry;
  /// [force] asks the provider for a new one, e.g. after a 401).
  Future<String?> idToken({bool force = false});

  /// [testEmail]/[testName] are only used by the local emulator (test account).
  Future<void> signInWithGoogle({String? testEmail, String? testName});
  Future<void> signInWithFacebook();
  Future<void> signInWithEmail(String email, String password);
  Future<void> registerWithEmail(String email, String password);
  Future<void> signOut();

  /// Completes when the persisted session (if any) has been restored.
  Future<void> get ready;
}
