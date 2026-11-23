import 'auth_gateway.dart';

/// Used when Firebase cannot start (e.g. offline). Never pretends to sign anyone in.
class DisabledAuthGateway extends AuthGateway {
  @override
  AuthUser? get currentUser => null;
  @override
  String get mode => 'disabled';
  @override
  bool get googleEnabled => false;
  @override
  bool get facebookEnabled => false;
  @override
  Future<void> get ready async {}
  @override
  Future<String?> idToken({bool force = false}) async => null;
  Never _off() => throw const AuthException(AuthFailure.providerDisabled);
  @override
  Future<void> signInWithGoogle({String? testEmail, String? testName}) async =>
      _off();
  @override
  Future<void> signInWithFacebook() async => _off();
  @override
  Future<void> signInWithEmail(String email, String password) async => _off();
  @override
  Future<void> registerWithEmail(String email, String password) async => _off();
  @override
  Future<void> signOut() async {}
}
