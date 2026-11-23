/// A live SSE connection.
abstract class EventStream {
  void close();
}

/// No SSE outside the browser: the controller long-polls instead.
EventStream? openEventStream(
  Uri uri, {
  required void Function(int id, String type) onEvent,
  required void Function() onError,
}) => null;
