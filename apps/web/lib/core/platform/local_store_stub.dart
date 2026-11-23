final _mem = <String, String>{};

Future<void> initLocalStore() async {}

String? readLocal(String key) => _mem[key];
void writeLocal(String key, String? value) =>
    value == null ? _mem.remove(key) : _mem[key] = value;
