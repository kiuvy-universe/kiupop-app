import 'dart:typed_data';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/network/api_client.dart';
import '../../storefront/data/storefront_models.dart';
import 'agent_models.dart';

/// Kiu agent endpoints. Every call carries a fresh KiuPop ID token.
class AgentApi {
  AgentApi(this._api, this._auth);
  final ApiClient _api;
  final AuthGateway _auth;

  /// Calls with a fresh token; on 401 refreshes once, and if the provider
  /// still rejects the session, signs out (the router sends the user to login).
  Future<ApiResult<T>> _authed<T>(
    Future<ApiResult<T>> Function(String token) call,
  ) async {
    var token = await _auth.idToken();
    if (token == null) return _signedOut();
    var res = await call(token);
    if (res case ApiFailure(statusCode: 401)) {
      token = await _auth.idToken(force: true);
      if (token == null) return _signedOut();
      res = await call(token);
      if (res case ApiFailure(statusCode: 401)) return _signedOut();
    }
    return res;
  }

  Future<ApiResult<T>> _signedOut<T>() async {
    await _auth.signOut();
    return const ApiFailure(ApiFailureKind.server, statusCode: 401);
  }

  String _s(String id) => '/api/v1/agent/sessions/${Uri.encodeComponent(id)}';

  Future<ApiResult<AgentSession>> start() => _authed(
    (t) => _api.postJson(
      '/api/v1/agent/sessions',
      const <String, Object>{},
      AgentSession.fromJson,
      token: t,
    ),
  );

  /// Latest session (live or published); 404 when the user never started one.
  Future<ApiResult<AgentSession>> current() => _authed(
    (t) => _api.getJson(
      '/api/v1/agent/sessions/current',
      AgentSession.fromJson,
      token: t,
    ),
  );

  Future<ApiResult<AgentSession>> get(String id) =>
      _authed((t) => _api.getJson(_s(id), AgentSession.fromJson, token: t));

  Future<ApiResult<AgentSession>> send(
    String id,
    String text,
    String clientMessageId,
  ) => _authed(
    (t) => _api.postJson(
      '${_s(id)}/messages',
      {'text': text, 'client_message_id': clientMessageId},
      AgentSession.fromJson,
      token: t,
      timeout: const Duration(seconds: 20),
    ),
  );

  Future<ApiResult<List<AgentEvent>>> events(
    String id,
    int after, {
    int wait = 8,
  }) => _authed(
    (t) => _api.getJson(
      '${_s(id)}/events?after=$after&wait=$wait',
      (j) => [
        for (final e in j['events'] as List)
          AgentEvent.fromJson(e as Map<String, dynamic>),
      ],
      token: t,
      timeout: Duration(seconds: wait + 5),
    ),
  );

  Future<ApiResult<String>> streamTicket(String id) => _authed(
    (t) => _api.postJson(
      '${_s(id)}/stream-ticket',
      const <String, Object>{},
      (j) => j['ticket'] as String,
      token: t,
    ),
  );

  Uri streamUri(String ticket, int after) => _api.resolve(
    '/api/v1/agent/stream?ticket=${Uri.encodeComponent(ticket)}&after=$after',
  );

  Future<ApiResult<SharedFile>> upload(
    String id,
    Uint8List bytes,
    String filename, {
    void Function(double sent)? onProgress,
    Future<void>? abort,
  }) => _authed(
    (t) => _api.uploadFile(
      '${_s(id)}/attachments',
      field: 'file',
      bytes: bytes,
      filename: filename,
      decode: SharedFile.fromJson,
      token: t,
      onProgress: onProgress,
      abort: abort,
    ),
  );

  Future<ApiResult<StorefrontView>> preview(String id) => _authed(
    (t) => _api.getJson('${_s(id)}/preview', StorefrontView.fromJson, token: t),
  );

  /// Test-mode payment for the paywall: activates the store's monthly plan.
  Future<ApiResult<PaywallInfo>> activatePlan(String id) => _authed(
    (t) => _api.postJson(
      '${_s(id)}/plan',
      {'confirm': true},
      PaywallInfo.fromJson,
      token: t,
    ),
  );

  Future<ApiResult<PublishResult>> publish(String id) => _authed(
    (t) => _api.postJson(
      '${_s(id)}/publish',
      {'confirm': true},
      PublishResult.fromJson,
      token: t,
    ),
  );
}
