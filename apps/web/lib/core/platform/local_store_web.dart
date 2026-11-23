import 'package:web/web.dart' as web;

Future<void> initLocalStore() async {}

String? readLocal(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } on Object {
    return null; // private mode / blocked storage: behave as signed out
  }
}

void writeLocal(String key, String? value) {
  try {
    value == null
        ? web.window.localStorage.removeItem(key)
        : web.window.localStorage.setItem(key, value);
  } on Object {
    // ignore: storage unavailable
  }
}
