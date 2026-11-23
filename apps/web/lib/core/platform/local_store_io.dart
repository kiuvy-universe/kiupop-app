import 'package:shared_preferences/shared_preferences.dart';

// Android/iOS: SharedPreferences, loaded once in main() so reads stay
// synchronous. Until then (or in VM tests) it behaves as memory only.
SharedPreferencesWithCache? _prefs;
final _mem = <String, String>{};

Future<void> initLocalStore() async {
  try {
    _prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
  } on Object {
    _prefs = null; // no plugin (tests): memory only
  }
}

String? readLocal(String key) => _prefs?.getString(key) ?? _mem[key];

void writeLocal(String key, String? value) {
  if (value == null) {
    _mem.remove(key);
    _prefs?.remove(key);
  } else {
    _mem[key] = value;
    _prefs?.setString(key, value);
  }
}
