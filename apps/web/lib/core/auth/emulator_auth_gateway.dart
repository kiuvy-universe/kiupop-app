import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../platform/local_store.dart';
import 'auth_gateway.dart';

/// Local-only sign-in against the Firebase Auth Emulator's REST API.
///
/// Why not the Firebase web SDK here: on reload the SDK restores the saved user
/// against Google's real endpoints *before* the emulator is connected, which
/// breaks the session and sends test tokens to Google. Talking to the emulator
/// directly avoids both. Production uses [FirebaseAuthGateway] (real project).
class EmulatorAuthGateway extends AuthGateway {
  EmulatorAuthGateway({
    required String host,
    http.Client? client,
    this.facebookEnabled = false,
  }) : _base = 'http://$host',
       _http = client ?? http.Client() {
    _restore();
  }

  static const _storeKey = 'kiupop.emulator.session';
  final String _base;
  final http.Client _http;
  @override
  final bool facebookEnabled;

  AuthUser? _user;
  String? _idToken;
  String? _refreshToken;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String get mode => 'emulator';
  @override
  bool get googleEnabled => true;
  @override
  AuthUser? get currentUser => _user;
  @override
  Future<void> get ready async {}

  void _restore() {
    final raw = readLocal(_storeKey);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _refreshToken = j['refresh_token'] as String;
      _user = AuthUser(
        uid: j['uid'] as String,
        email: j['email'] as String? ?? '',
        name: j['name'] as String?,
      );
    } on Object {
      writeLocal(_storeKey, null);
    }
  }

  void _save() => writeLocal(
    _storeKey,
    _user == null
        ? null
        : jsonEncode({
            'refresh_token': _refreshToken,
            'uid': _user!.uid,
            'email': _user!.email,
            'name': _user!.name,
          }),
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Object body, {
    bool form = false,
  }) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$_base/$path?key=emulator'),
            headers: {
              'Content-Type': form
                  ? 'application/x-www-form-urlencoded'
                  : 'application/json',
            },
            body: form ? body : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
    } on Object {
      throw const AuthException(AuthFailure.network);
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final msg =
          ((j['error'] as Map<String, dynamic>?)?['message'] as String? ?? '')
              .split(' ')
              .first;
      throw AuthException(switch (msg) {
        'EMAIL_EXISTS' => AuthFailure.emailInUse,
        'INVALID_LOGIN_CREDENTIALS' ||
        'INVALID_PASSWORD' ||
        'EMAIL_NOT_FOUND' => AuthFailure.invalidCredentials,
        'WEAK_PASSWORD' => AuthFailure.weakPassword,
        'INVALID_EMAIL' => AuthFailure.invalidEmail,
        _ => AuthFailure.unknown,
      });
    }
    return j;
  }

  void _signedIn(Map<String, dynamic> j) {
    _idToken = j['idToken'] as String;
    _refreshToken = j['refreshToken'] as String;
    _expires = DateTime.now().add(
      Duration(seconds: int.tryParse('${j['expiresIn']}') ?? 3600),
    );
    _user = AuthUser(
      uid: j['localId'] as String,
      email: j['email'] as String? ?? '',
      name: j['displayName'] as String?,
    );
    _save();
    notifyListeners();
  }

  @override
  Future<String?> idToken({bool force = false}) async {
    if (_user == null || _refreshToken == null) return null;
    if (!force &&
        _idToken != null &&
        DateTime.now().isBefore(
          _expires.subtract(const Duration(minutes: 5)),
        )) {
      return _idToken;
    }
    try {
      final j = await _post(
        'securetoken.googleapis.com/v1/token',
        'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(_refreshToken!)}',
        form: true,
      );
      _idToken = j['id_token'] as String;
      _refreshToken = j['refresh_token'] as String;
      _expires = DateTime.now().add(
        Duration(seconds: int.tryParse('${j['expires_in']}') ?? 3600),
      );
      _save();
      return _idToken;
    } on AuthException {
      return null; // emulator reset or account deleted: sign in again
    }
  }

  @override
  Future<void> registerWithEmail(String email, String password) async =>
      _signedIn(
        await _post('identitytoolkit.googleapis.com/v1/accounts:signUp', {
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

  @override
  Future<void> signInWithEmail(String email, String password) async =>
      _signedIn(
        await _post(
          'identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',
          {'email': email, 'password': password, 'returnSecureToken': true},
        ),
      );

  /// Emulator "Google" account: no real Google involved (the emulator accepts a
  /// test identity). The login page asks for the test name and email.
  @override
  Future<void> signInWithGoogle({String? testEmail, String? testName}) async {
    final email = (testEmail ?? '').trim();
    if (!email.contains('@')) {
      throw const AuthException(AuthFailure.invalidEmail);
    }
    final idToken = jsonEncode({
      'sub': 'google-${email.toLowerCase()}',
      'email': email,
      'email_verified': true,
      'name': (testName ?? '').trim(),
    });
    _signedIn(
      await _post('identitytoolkit.googleapis.com/v1/accounts:signInWithIdp', {
        'postBody':
            'id_token=${Uri.encodeQueryComponent(idToken)}&providerId=google.com',
        'requestUri': 'http://localhost',
        'returnIdpCredential': true,
        'returnSecureToken': true,
      }),
    );
  }

  @override
  Future<void> signInWithFacebook() async =>
      throw const AuthException(AuthFailure.providerDisabled);

  @override
  Future<void> signOut() async {
    _user = null;
    _idToken = null;
    _refreshToken = null;
    _save();
    notifyListeners();
  }
}
