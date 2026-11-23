import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A live SSE connection.
abstract class EventStream {
  void close();
}

class _WebEventStream implements EventStream {
  _WebEventStream(this._es);
  final web.EventSource _es;
  @override
  void close() => _es.close();
}

const _types = [
  'message.created',
  'progress',
  'preview.updated',
  'store.ready',
  'store.published',
];

/// Browser EventSource (reconnects by itself and resumes with Last-Event-ID).
EventStream? openEventStream(
  Uri uri, {
  required void Function(int id, String type) onEvent,
  required void Function() onError,
}) {
  final es = web.EventSource(uri.toString());
  for (final t in _types) {
    es.addEventListener(
      t,
      ((web.Event e) {
        final id = int.tryParse((e as web.MessageEvent).lastEventId) ?? 0;
        onEvent(id, t);
      }).toJS,
    );
  }
  es.onerror = ((web.Event _) => onError()).toJS;
  return _WebEventStream(es);
}
