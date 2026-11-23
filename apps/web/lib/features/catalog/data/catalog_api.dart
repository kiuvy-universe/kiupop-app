import '../../../core/network/api_client.dart';
import '../../products/data/product_models.dart';
import '../../stores/data/store_models.dart';

/// Server-computed order preview (never trust client prices).
class OrderPreview {
  const OrderPreview({
    required this.totalMinor,
    required this.message,
    required this.whatsappUrl,
  });

  factory OrderPreview.fromJson(Map<String, dynamic> j) => OrderPreview(
    totalMinor: j['total_minor'] as int,
    message: j['message'] as String,
    whatsappUrl: Uri.parse(j['whatsapp_url'] as String),
  );

  final int totalMinor;
  final String message;
  final Uri whatsappUrl;
}

/// Public, unauthenticated catalog access.
class CatalogApi {
  const CatalogApi(this._api);

  final ApiClient _api;

  Future<ApiResult<PublicStore>> store(String slug) => _api.getJson(
    '/api/v1/stores/${Uri.encodeComponent(slug)}',
    PublicStore.fromJson,
  );

  Future<ApiResult<List<PublicProduct>>> products(String slug) => _api.getJson(
    '/api/v1/public/stores/${Uri.encodeComponent(slug)}/products',
    (j) => decodeList(j, PublicProduct.fromJson),
  );

  /// Sends only ids and quantities; the server prices everything.
  Future<ApiResult<OrderPreview>> preview(
    String slug,
    Map<String, int> quantities,
  ) => _api.postJson(
    '/api/v1/public/stores/${Uri.encodeComponent(slug)}/orders/preview',
    {
      'items': [
        for (final e in quantities.entries)
          {'product_id': e.key, 'quantity': e.value},
      ],
    },
    OrderPreview.fromJson,
  );

  Uri? imageUri(String? path) => path == null ? null : _api.resolve(path);
}
