import 'package:flutter/foundation.dart';

import '../../products/data/product_models.dart';

/// Shopper cart for one store. Totals here are an estimate for display only;
/// the order preview endpoint recomputes everything from the database.
class Cart extends ChangeNotifier {
  static const int maxQuantity = 99;

  final Map<String, PublicProduct> _products = {};
  final Map<String, int> _qty = {};

  bool get isEmpty => _qty.isEmpty;
  int get itemCount => _qty.values.fold(0, (a, b) => a + b);
  Map<String, int> get quantities => Map.unmodifiable(_qty);
  List<PublicProduct> get products => [
    for (final id in _qty.keys) _products[id]!,
  ];

  int quantityOf(String id) => _qty[id] ?? 0;
  int subtotalOf(String id) =>
      (_products[id]?.priceMinor ?? 0) * quantityOf(id);
  int get estimatedTotal =>
      _qty.keys.fold(0, (sum, id) => sum + subtotalOf(id));

  void add(PublicProduct p) {
    _products[p.id] = p;
    final next = quantityOf(p.id) + 1;
    if (next > maxQuantity) return;
    _qty[p.id] = next;
    notifyListeners();
  }

  void decrement(String id) {
    final q = quantityOf(id);
    if (q <= 1) {
      remove(id);
      return;
    }
    _qty[id] = q - 1;
    notifyListeners();
  }

  void remove(String id) {
    _qty.remove(id);
    _products.remove(id);
    notifyListeners();
  }

  /// Drops lines whose product is no longer offered.
  void retainOnly(Set<String> availableIds) {
    final before = _qty.length;
    _qty.removeWhere((id, _) => !availableIds.contains(id));
    _products.removeWhere((id, _) => !availableIds.contains(id));
    if (_qty.length != before) notifyListeners();
  }

  void clear() {
    _qty.clear();
    _products.clear();
    notifyListeners();
  }
}
