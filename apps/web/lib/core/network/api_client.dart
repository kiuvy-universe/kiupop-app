import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Why a request failed. UI maps these to friendly copy; no raw errors shown.
enum ApiFailureKind { unreachable, timeout, server, badResponse, cancelled }

/// Result of an API call: either [ApiSuccess] or [ApiFailure].
sealed class ApiResult<T> {
  const ApiResult();
}

final class ApiSuccess<T> extends ApiResult<T> {
  const ApiSuccess(this.value);
  final T value;
}

final class ApiFailure<T> extends ApiResult<T> {
  const ApiFailure(
    this.kind, {
    this.statusCode,
    this.code,
    this.message,
    this.fields = const {},
  });
  final ApiFailureKind kind;
  final int? statusCode;

  /// Stable machine code from the API error envelope, when present.
  final String? code;

  /// Human message (es-CR) from the API, safe to show.
  final String? message;

  /// Per-field validation messages (422 validation_failed).
  final Map<String, String> fields;

  /// Re-types the failure for another result type.
  ApiFailure<R> cast<R>() => ApiFailure<R>(
    kind,
    statusCode: statusCode,
    code: code,
    message: message,
    fields: fields,
  );
}

/// Minimal JSON HTTP client with timeout, typed decoding and optional bearer
/// credential. The credential is passed per call and never put in URLs.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;
  final Duration timeout;

  /// Resolves a server-relative path (e.g. an image_url) against the API.
  Uri resolve(String path) => baseUrl.resolve(path);

  Future<ApiResult<T>> getJson<T>(
    String path,
    T Function(Map<String, dynamic> json) decode, {
    String? token,
    Duration? timeout,
  }) => _send('GET', path, decode, token: token, timeout: timeout);

  Future<ApiResult<T>> postJson<T>(
    String path,
    Object body,
    T Function(Map<String, dynamic> json) decode, {
    String? token,
    Duration? timeout,
  }) => _send('POST', path, decode, token: token, body: body, timeout: timeout);

  Future<ApiResult<T>> patchJson<T>(
    String path,
    Object body,
    T Function(Map<String, dynamic> json) decode, {
    String? token,
  }) => _send('PATCH', path, decode, token: token, body: body);

  /// POSTs raw bytes (e.g. a voice note) with an explicit content type.
  Future<ApiResult<T>> postBytes<T>(
    String path,
    Uint8List bytes, {
    required String contentType,
    required T Function(Map<String, dynamic> json) decode,
    String? token,
    Duration? timeout,
  }) => _run(
    () => _http.post(
      resolve(path),
      headers: {..._headers(token, json: false), 'Content-Type': contentType},
      body: bytes,
    ),
    decode,
    timeout: timeout,
  );

  /// POSTs JSON where success has no body (204). Failures are ignored by callers.
  Future<bool> postNoContent(String path, Object body, {String? token}) async {
    try {
      final res = await _http
          .post(
            resolve(path),
            headers: _headers(token, json: true),
            body: jsonEncode(body),
          )
          .timeout(timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } on Object {
      return false;
    }
  }

  Future<ApiResult<T>> uploadFile<T>(
    String path, {
    required String field,
    required Uint8List bytes,
    required String filename,
    required T Function(Map<String, dynamic> json) decode,
    String? token,
    void Function(double sent)? onProgress,
    Future<void>? abort,
  }) async {
    final req = http.MultipartRequest('POST', resolve(path))
      ..headers.addAll(_headers(token, json: false))
      ..files.add(
        http.MultipartFile.fromBytes(field, bytes, filename: filename),
      );
    // A dedicated client per upload can be closed to really abort the request.
    final client = abort == null ? _http : _uploadClient();
    var aborted = false;
    if (abort != null) {
      unawaited(
        abort.then((_) {
          aborted = true;
          if (!identical(client, _http)) client.close();
        }),
      );
    }
    Future<http.Response> send() async {
      if (onProgress == null) {
        return http.Response.fromStream(await client.send(req));
      }
      final body = req.finalize();
      final total = req.contentLength;
      var sent = 0;
      final streamed = http.StreamedRequest('POST', req.url)
        ..headers.addAll(req.headers)
        ..contentLength = total;
      body.listen(
        (chunk) {
          sent += chunk.length;
          onProgress(total == 0 ? 1 : sent / total);
          streamed.sink.add(chunk);
        },
        onDone: streamed.sink.close,
        onError: streamed.sink.addError,
        cancelOnError: true,
      );
      return http.Response.fromStream(await client.send(streamed));
    }

    final res = await _run(send, decode, timeout: const Duration(seconds: 60));
    if (!identical(client, _http)) client.close(); // per-upload client: done
    if (aborted) return const ApiFailure(ApiFailureKind.cancelled);
    return res;
  }

  /// Factory for per-upload clients (tests inject the shared mock instead).
  http.Client Function() get _uploadClient =>
      uploadClientFactory ?? () => _http;

  /// Production sets this so an upload can be aborted without closing the
  /// shared client.
  http.Client Function()? uploadClientFactory;

  Future<ApiResult<T>> _send<T>(
    String method,
    String path,
    T Function(Map<String, dynamic> json) decode, {
    String? token,
    Object? body,
    Duration? timeout,
  }) {
    final uri = resolve(path);
    final headers = _headers(token, json: body != null);
    final encoded = body == null ? null : jsonEncode(body);
    return _run(
      () => switch (method) {
        'POST' => _http.post(uri, headers: headers, body: encoded),
        'PATCH' => _http.patch(uri, headers: headers, body: encoded),
        _ => _http.get(uri, headers: headers),
      },
      decode,
      timeout: timeout,
    );
  }

  Map<String, String> _headers(String? token, {required bool json}) => {
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<ApiResult<T>> _run<T>(
    Future<http.Response> Function() call,
    T Function(Map<String, dynamic> json) decode, {
    Duration? timeout,
  }) async {
    final http.Response res;
    try {
      res = await call().timeout(timeout ?? this.timeout);
    } on TimeoutException {
      return const ApiFailure(ApiFailureKind.timeout);
    } on Exception {
      return const ApiFailure(ApiFailureKind.unreachable);
    }

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      body = null;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final error = body?['error'];
      if (error is Map<String, dynamic>) {
        final fields = error['fields'];
        return ApiFailure(
          ApiFailureKind.server,
          statusCode: res.statusCode,
          code: error['code'] as String?,
          message: error['message'] as String?,
          fields: fields is Map<String, dynamic>
              ? fields.map((k, v) => MapEntry(k, '$v'))
              : const {},
        );
      }
      return ApiFailure(ApiFailureKind.server, statusCode: res.statusCode);
    }
    if (body == null) {
      return ApiFailure(ApiFailureKind.badResponse, statusCode: res.statusCode);
    }
    try {
      return ApiSuccess(decode(body));
    } on Object {
      return ApiFailure(ApiFailureKind.badResponse, statusCode: res.statusCode);
    }
  }

  void close() => _http.close();
}
