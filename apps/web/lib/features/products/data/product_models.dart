/// Mirrors AdminProduct / PublicProduct / AISuggestion in the OpenAPI contract.
class AdminProduct {
  const AdminProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.priceMinor,
    required this.currency,
    required this.imageUrl,
    required this.available,
  });

  factory AdminProduct.fromJson(Map<String, dynamic> j) => AdminProduct(
    id: j['id'] as String,
    name: j['name'] as String,
    description: j['description'] as String,
    priceMinor: j['price_minor'] as int,
    currency: j['currency'] as String,
    imageUrl: j['image_url'] as String?,
    available: j['available'] as bool,
  );

  final String id;
  final String name;
  final String description;
  final int priceMinor;
  final String currency;
  final String? imageUrl;
  final bool available;
}

class PublicProduct {
  const PublicProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.priceMinor,
    required this.currency,
    required this.imageUrl,
  });

  factory PublicProduct.fromJson(Map<String, dynamic> j) => PublicProduct(
    id: j['id'] as String,
    name: j['name'] as String,
    description: j['description'] as String,
    priceMinor: j['price_minor'] as int,
    currency: j['currency'] as String,
    imageUrl: j['image_url'] as String?,
  );

  final String id;
  final String name;
  final String description;
  final int priceMinor;
  final String currency;
  final String? imageUrl;
}

List<T> decodeList<T>(
  Map<String, dynamic> j,
  T Function(Map<String, dynamic>) f,
) => (j['data'] as List<dynamic>)
    .map((e) => f(e as Map<String, dynamic>))
    .toList(growable: false);

class AiSuggestion {
  const AiSuggestion({
    required this.name,
    required this.shortDescription,
    required this.marketingText,
  });

  factory AiSuggestion.fromJson(Map<String, dynamic> j) => AiSuggestion(
    name: j['name'] as String,
    shortDescription: j['short_description'] as String,
    marketingText: j['marketing_text'] as String,
  );

  final String name;
  final String shortDescription;
  final String marketingText;

  /// Description text the merchant can accept (and then edit).
  String get description => marketingText.isEmpty
      ? shortDescription
      : '$shortDescription $marketingText';
}
