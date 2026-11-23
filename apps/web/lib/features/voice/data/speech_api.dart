import 'dart:typed_data';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/network/api_client.dart';

/// What the server says about voice notes.
class SpeechStatus {
  const SpeechStatus({
    required this.enabled,
    required this.provider,
    required this.maxSeconds,
  });
  factory SpeechStatus.fromJson(Map<String, dynamic> j) => SpeechStatus(
    enabled: j['enabled'] as bool? ?? false,
    provider: j['provider'] as String? ?? 'disabled',
    maxSeconds: j['max_seconds'] as int? ?? 60,
  );
  static const off = SpeechStatus(
    enabled: false,
    provider: 'disabled',
    maxSeconds: 60,
  );
  final bool enabled;
  final String provider;
  final int maxSeconds;
}

/// A transcript to review (mirrors examples/speech_transcription.json).
class Transcript {
  const Transcript({
    required this.text,
    required this.provider,
    required this.durationMs,
    required this.latencyMs,
  });
  factory Transcript.fromJson(Map<String, dynamic> j) => Transcript(
    text: j['text'] as String,
    provider: j['provider'] as String,
    durationMs: j['duration_ms'] as int? ?? 0,
    latencyMs: j['latency_ms'] as int? ?? 0,
  );
  final String text;
  final String provider;
  final int durationMs;
  final int latencyMs;
}

class SpeechApi {
  SpeechApi(this._api, this._auth);
  final ApiClient _api;
  final AuthGateway _auth;

  Future<ApiResult<T>> _authed<T>(
    Future<ApiResult<T>> Function(String token) call,
  ) async {
    final token = await _auth.idToken();
    if (token == null) {
      return const ApiFailure(ApiFailureKind.server, statusCode: 401);
    }
    return call(token);
  }

  Future<ApiResult<SpeechStatus>> status() => _authed(
    (t) =>
        _api.getJson('/api/v1/speech/status', SpeechStatus.fromJson, token: t),
  );

  Future<ApiResult<Transcript>> transcribe(
    Uint8List wav, {
    String? sessionId,
  }) => _authed(
    (t) => _api.postBytes(
      '/api/v1/speech/transcriptions'
      '${sessionId == null ? '' : '?session_id=${Uri.encodeQueryComponent(sessionId)}'}',
      wav,
      contentType: 'audio/wav',
      decode: Transcript.fromJson,
      token: t,
      timeout: const Duration(seconds: 50),
    ),
  );
}
