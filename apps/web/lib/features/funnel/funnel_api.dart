import 'dart:async';

import '../../core/auth/auth_gateway.dart';
import '../../core/network/api_client.dart';

/// Conversion milestones only the app can see. Fire-and-forget: analytics
/// never blocks or breaks the merchant's flow. Numbers only, no text.
class FunnelApi {
  FunnelApi(this._api, this._auth);
  final ApiClient _api;
  final AuthGateway _auth;

  void record(String event, {String? sessionId, Map<String, int>? meta}) {
    unawaited(_send(event, sessionId, meta));
  }

  Future<void> _send(
    String event,
    String? sessionId,
    Map<String, int>? meta,
  ) async {
    try {
      final token = await _auth.idToken();
      if (token == null) return;
      await _api.postNoContent('/api/v1/funnel/events', {
        'event': event,
        'session_id': ?sessionId,
        if (meta != null && meta.isNotEmpty) 'meta': meta,
      }, token: token);
    } on Object {
      // analytics must never surface errors to the merchant
    }
  }
}
