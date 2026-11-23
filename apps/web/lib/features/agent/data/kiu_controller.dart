import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/platform/platform_actions.dart' show PickedFile;
import '../../storefront/data/storefront_models.dart';
import 'agent_api.dart';
import 'agent_models.dart';
import 'event_stream.dart';

/// Holds the conversation with Kiu and follows the backend's progress events.
/// The UI only animates what the backend confirmed (POP fires on store.ready).
class KiuController extends ChangeNotifier {
  KiuController(this._api, {this.useSse = true, Random? random})
    : _random = random ?? Random.secure();

  final AgentApi _api;
  final bool useSse;
  final Random _random;

  AgentSession? session;
  StorefrontView? preview;
  ApiFailure<Object?>? loadFailure;
  ApiFailure<Object?>? previewFailure;
  ApiFailure<Object?>? readinessFailure;
  String? sendError;
  bool sending = false;
  bool publishing = false;
  bool paying = false;
  String? pendingText;

  /// True once store.ready arrives live in this page (not on reload).
  bool popRequested = false;
  bool _readyEventSeen = false;
  bool _readyAtLoad = false;
  bool _popOffered = false;
  bool _retriedReadiness = false;

  int _lastEvent = 0;
  EventStream? _stream;
  Timer? _poll;
  Timer? _refresh;
  bool _disposed = false;
  bool _needPreview = false;
  int _gen = 0; // bumps on every start(): stale async work is ignored

  /// Upload problems to show (too many files, too large, unsupported…).
  final uploadErrors = <String>[];

  /// Files on their way to Kiu (in flight or failed and retryable).
  final pendingUploads = <PendingUpload>[];
  int _uploadSeq = 0;

  /// Uploads still in flight.
  int get uploading => pendingUploads.where((u) => !u.failed).length;

  /// Resumes the latest session (a reload after publishing shows the share
  /// card again); starts a new one only when there is none.
  Future<void> start({bool fresh = false}) async {
    final gen = ++_gen;
    loadFailure = null;
    readinessFailure = null;
    _retriedReadiness = false;
    _stream?.close();
    _stream = null;
    _poll?.cancel();
    _refresh?.cancel();
    _reopen?.cancel();
    notifyListeners();
    ApiResult<AgentSession> res;
    try {
      res = fresh ? await _api.start() : await _api.current();
    } on Object {
      res = const ApiFailure(ApiFailureKind.unreachable);
    }
    if (_disposed || gen != _gen) return;
    if (res case ApiFailure(statusCode: 404)) {
      res = await _api.start();
      if (_disposed || gen != _gen) return;
    }
    switch (res) {
      case ApiSuccess(:final value):
        session = value;
        preview = null;
        previewFailure = null;
        sendError = null;
        uploadErrors.clear();
        pendingUploads.clear();
        popRequested = false;
        _readyEventSeen = false;
        _popOffered = false;
        _readyAtLoad = value.ready || value.published;
        // The session and its event watermark are separate reads. Follow the
        // entire feed until the first readiness so the watermark cannot skip it.
        _lastEvent = _readyAtLoad || value.toReadyMs != null
            ? value.lastEventId
            : 0;
        if (value.ready || value.published) await loadPreview();
        if (_disposed || gen != _gen) return;
        _follow();
      case final ApiFailure<AgentSession> f:
        loadFailure = f;
    }
    notifyListeners();
  }

  String _clientId() =>
      List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();

  Future<bool> send(String text) async {
    final s = session;
    final t = text.trim();
    if (s == null || t.isEmpty || sending) return false;
    sending = true;
    sendError = null;
    pendingText = t;
    notifyListeners();
    final gen = _gen;
    final res = await _api.send(s.id, t, _clientId());
    if (_disposed || gen != _gen) return false;
    sending = false;
    pendingText = null;
    switch (res) {
      case ApiSuccess(:final value):
        if (value.revision >= (session?.revision ?? 0)) session = value;
        notifyListeners();
        return true;
      case final ApiFailure<AgentSession> f:
        sendError = f.message ?? '';
        notifyListeners();
        return false;
    }
  }

  Future<void> loadPreview() async {
    final s = session;
    if (s == null) return;
    final gen = _gen;
    final res = await _api.preview(s.id);
    if (_disposed || gen != _gen) return;
    switch (res) {
      case ApiSuccess(:final value):
        preview = value;
        previewFailure = null;
      case final ApiFailure<StorefrontView> failure:
        previewFailure = failure;
    }
    notifyListeners();
  }

  /// Runs the paywall's test payment, then reloads the session.
  Future<ApiResult<PaywallInfo>> activatePlan() async {
    final s = session!;
    paying = true;
    notifyListeners();
    final res = await _api.activatePlan(s.id);
    if (_disposed) return res;
    paying = false;
    notifyListeners();
    await _reload();
    return res;
  }

  Future<ApiResult<PublishResult>> publish() async {
    final s = session!;
    publishing = true;
    notifyListeners();
    final res = await _api.publish(s.id);
    if (_disposed) return res;
    publishing = false;
    notifyListeners();
    await _reload();
    return res;
  }

  /// Uploads files in parallel after client-side limit checks (the server
  /// re-checks): file count, total bytes per store and per-file size.
  Future<void> upload(
    List<PickedFile> files, {
    required String Function(String name) tooMany,
    required String Function(String name) tooBig,
    String Function(String name, int mb)? tooManyBytes,
  }) async {
    final s = session;
    if (s == null || files.isEmpty) return;
    uploadErrors.clear();
    var count = s.files.length + uploading;
    var bytes =
        s.files.fold<int>(0, (n, f) => n + f.sizeBytes) +
        pendingUploads.fold<int>(0, (n, u) => n + u.file.bytes.length);
    final ok = <PendingUpload>[];
    for (final f in files) {
      if (count >= s.maxFiles) {
        uploadErrors.add(tooMany(f.name));
      } else if (f.bytes.length > 20 << 20) {
        uploadErrors.add(tooBig(f.name));
      } else if (bytes + f.bytes.length > s.maxFileBytes) {
        uploadErrors.add(
          (tooManyBytes ?? (n, _) => tooBig(n))(f.name, s.maxFileBytes >> 20),
        );
      } else {
        ok.add(PendingUpload._(++_uploadSeq, f));
        count++;
        bytes += f.bytes.length;
      }
    }
    pendingUploads.addAll(ok);
    notifyListeners();
    await Future.wait([for (final u in ok) _send(u)]);
    if (_disposed) return;
    await _reload();
    notifyListeners();
  }

  Future<void> _send(PendingUpload u) async {
    final s = session;
    if (s == null) return;
    u
      ..failed = false
      ..error = null
      ..progress = 0
      ..abort = Completer<void>();
    var last = 0.0;
    final res = await _api.upload(
      s.id,
      u.file.bytes,
      u.file.name,
      onProgress: (p) {
        u.progress = p;
        if (p - last >= .05 || p >= 1) {
          last = p;
          if (!_disposed) notifyListeners();
        }
      },
      abort: u.abort!.future,
    );
    if (_disposed) return;
    switch (res) {
      case ApiSuccess():
        pendingUploads.remove(u);
      case ApiFailure(kind: ApiFailureKind.cancelled):
        pendingUploads.remove(u);
      case ApiFailure(:final message):
        u
          ..failed = true
          ..error = (message ?? '').trim();
    }
    notifyListeners();
  }

  /// Stops an upload in flight (the request is aborted).
  void cancelUpload(PendingUpload u) {
    if (u.failed) return;
    final a = u.abort;
    if (a != null && !a.isCompleted) a.complete();
  }

  /// Tries a failed upload again.
  Future<void> retryUpload(PendingUpload u) async {
    if (!u.failed) return;
    notifyListeners();
    await _send(u);
    if (!_disposed) await _reload();
  }

  /// Forgets a failed upload.
  void removeUpload(PendingUpload u) {
    pendingUploads.remove(u);
    notifyListeners();
  }

  void consumePop() {
    popRequested = false;
    notifyListeners();
  }

  // --- live progress ----------------------------------------------------------

  void _follow() {
    if (_disposed) return;
    if (useSse) {
      _openSse();
    } else {
      _schedulePoll(Duration.zero);
    }
  }

  Future<void> _openSse() async {
    final s = session;
    final gen = _gen;
    if (s == null) return;
    final ticket = await _api.streamTicket(s.id);
    if (_disposed || gen != _gen) return;
    if (ticket case ApiSuccess(:final value)) {
      _stream = openEventStream(
        _api.streamUri(value, _lastEvent),
        onEvent: _onEvent,
        onError: () {
          // Tickets expire and servers restart: drop this stream, catch up by
          // polling, and reopen with a fresh ticket (resumes from _lastEvent).
          _stream?.close();
          _stream = null;
          _schedulePoll(Duration.zero);
          _reopen?.cancel();
          _reopen = Timer(const Duration(seconds: 3), () {
            if (!_disposed && gen == _gen) _openSse();
          });
        },
      );
    }
    if (_stream == null) _schedulePoll(Duration.zero);
  }

  Timer? _reopen;

  void _schedulePoll(Duration d) {
    if (_disposed || (_poll?.isActive ?? false)) return;
    _poll = Timer(d, _pollOnce);
  }

  Future<void> _pollOnce() async {
    final s = session;
    if (s == null || _disposed) return;
    final gen = _gen;
    final res = await _api.events(s.id, _lastEvent, wait: useSse ? 0 : 8);
    if (_disposed || gen != _gen) return;
    var got = false;
    if (res case ApiSuccess(:final value)) {
      for (final e in value) {
        _onEvent(e.id, e.type);
        got = true;
      }
    }
    if (_stream == null) {
      _schedulePoll(Duration(milliseconds: got ? 100 : 900));
    }
  }

  void _onEvent(int id, String type) {
    if (id <= _lastEvent) return;
    _lastEvent = id;
    if (type == 'store.ready') _readyEventSeen = true;
    if (type == 'preview.updated' ||
        type == 'store.ready' ||
        type == 'store.published') {
      _needPreview = true;
    }
    _refresh?.cancel();
    _refresh = Timer(const Duration(milliseconds: 120), _reload);
  }

  Future<void> retryReadiness() async {
    _refresh?.cancel();
    _retriedReadiness = false;
    readinessFailure = null;
    notifyListeners();
    await _reload();
  }

  Future<void> _reload() async {
    final s = session;
    if (s == null || _disposed) return;
    final gen = _gen;
    final res = await _api.get(s.id);
    if (_disposed || gen != _gen) return;
    switch (res) {
      case ApiSuccess(:final value):
        if (value.revision < (session?.revision ?? 0)) return;
        session = value;
        readinessFailure = null;
        if (_readyEventSeen && !_readyAtLoad && !_popOffered && value.ready) {
          _popOffered = true;
          popRequested = !value.published && value.status != 'failed';
        }
        if (_needPreview || (value.ready && preview == null)) {
          _needPreview = false;
          await loadPreview();
        }
        if (!_disposed && gen == _gen) notifyListeners();
      case final ApiFailure<AgentSession> failure:
        if (!_readyEventSeen || _readyAtLoad || _popOffered) return;
        if (!_retriedReadiness) {
          _retriedReadiness = true;
          _refresh?.cancel();
          _refresh = Timer(const Duration(milliseconds: 600), _reload);
          return;
        }
        readinessFailure = failure;
        notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _refresh?.cancel();
    _reopen?.cancel();
    _stream?.close();
    super.dispose();
  }
}

/// One file on its way to Kiu.
class PendingUpload {
  PendingUpload._(this.id, this.file);
  final int id;
  final PickedFile file;
  double progress = 0;
  bool failed = false;
  String? error;
  Completer<void>? abort;
}
