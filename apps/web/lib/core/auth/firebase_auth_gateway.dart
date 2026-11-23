import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'auth_gateway.dart';

/// Firebase Auth for a KiuPop-dedicated project. Locally it talks to the
/// Firebase Auth Emulator (project demo-kiupop: no real accounts, no network).
class FirebaseAuthGateway extends AuthGateway {
  FirebaseAuthGateway._(this._auth, this._mode, this._facebook) {
    _sub = _auth.idTokenChanges().listen((u) {
      _user = u;
      if (u == null) _forcedOut = false;
      if (!_ready.isCompleted) _ready.complete();
      notifyListeners();
    });
  }

  /// Initialises Firebase from build-time defines (no secrets: web API keys are public identifiers).
  static Future<FirebaseAuthGateway> create({
    required String projectId,
    required String apiKey,
    required String appId,
    String emulatorHost = '',
    bool facebookEnabled = false,
  }) async {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: '000000000000',
        projectId: projectId,
        authDomain: '$projectId.firebaseapp.com',
      ),
    );
    final auth = FirebaseAuth.instance;
    const mode = 'firebase'; // local emulator: see EmulatorAuthGateway
    await auth.setPersistence(Persistence.LOCAL);
    return FirebaseAuthGateway._(auth, mode, facebookEnabled);
  }

  final FirebaseAuth _auth;
  final String _mode;
  final bool _facebook;
  final _ready = Completer<void>();
  late final StreamSubscription<User?> _sub;
  User? _user;

  /// Set when we signed the user out but the SDK could not (its local state can
  /// be stale, e.g. the emulator was reset). Cleared by the next real sign-in.
  bool _forcedOut = false;

  @override
  Future<void> get ready => _ready.future;

  /// The SDK's live user (not a cached copy), so a session the provider
  /// dropped is never shown as signed in.
  @override
  AuthUser? get currentUser {
    if (_forcedOut) return null;
    final u = _auth.currentUser ?? _user;
    if (_auth.currentUser == null) _user = null;
    if (u == null) return null;
    return AuthUser(uid: u.uid, email: u.email ?? '', name: u.displayName);
  }

  @override
  String get mode => _mode;

  @override
  bool get googleEnabled => true;

  @override
  bool get facebookEnabled => _facebook;

  @override
  Future<String?> idToken({bool force = false}) async {
    if (_forcedOut) return null;
    try {
      return await _auth.currentUser
          ?.getIdToken(force)
          .timeout(const Duration(seconds: 6));
    } on Object {
      return null; // refresh token revoked, provider reset or offline: sign in again
    }
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
      _forcedOut = false;
      _user = _auth.currentUser;
      notifyListeners();
    } on FirebaseAuthException catch (e) {
      throw AuthException(switch (e.code) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' ||
        'invalid-login-credentials' => AuthFailure.invalidCredentials,
        'email-already-in-use' => AuthFailure.emailInUse,
        'weak-password' => AuthFailure.weakPassword,
        'invalid-email' => AuthFailure.invalidEmail,
        'popup-closed-by-user' ||
        'cancelled-popup-request' ||
        'popup-blocked' => AuthFailure.popupClosed,
        'operation-not-allowed' => AuthFailure.providerDisabled,
        'network-request-failed' => AuthFailure.network,
        _ => AuthFailure.unknown,
      });
    }
  }

  @override
  Future<void> signInWithGoogle({String? testEmail, String? testName}) =>
      _guard(() async {
        await _auth.signInWithPopup(
          GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'}),
        );
      });

  @override
  Future<void> signInWithFacebook() async {
    if (!_facebook) throw const AuthException(AuthFailure.providerDisabled);
    await _guard(() async => _auth.signInWithPopup(FacebookAuthProvider()));
  }

  @override
  Future<void> signInWithEmail(String email, String password) => _guard(
    () async =>
        _auth.signInWithEmailAndPassword(email: email, password: password),
  );

  @override
  Future<void> registerWithEmail(String email, String password) => _guard(
    () async =>
        _auth.createUserWithEmailAndPassword(email: email, password: password),
  );

  @override
  Future<void> signOut() async {
    _forcedOut = true;
    _user = null;
    notifyListeners(); // the router re-evaluates guards right away
    try {
      await _auth.signOut().timeout(const Duration(seconds: 6));
    } on Object {
      // Local sign-out already happened; the SDK clears itself on next sign-in.
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
