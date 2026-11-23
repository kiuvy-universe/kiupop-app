import 'package:flutter/foundation.dart';

import '../stores/data/store_models.dart';

/// The signed-in merchant. Held in memory only (never localStorage/cookies):
/// reloading the page asks for the credential again. POC trade-off, see ADR-002.
class AdminSession extends ChangeNotifier {
  String? _token;
  AdminStore? _store;
  bool _aiEnabled = false;

  String? get token => _token;
  AdminStore? get store => _store;
  bool get aiEnabled => _aiEnabled;
  bool get isSignedIn => _token != null && _store != null;

  void signIn({
    required String token,
    required AdminStore store,
    required bool aiEnabled,
  }) {
    _token = token;
    _store = store;
    _aiEnabled = aiEnabled;
    notifyListeners();
  }

  void signOut() {
    _token = null;
    _store = null;
    _aiEnabled = false;
    notifyListeners();
  }
}
