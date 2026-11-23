import 'dart:typed_data';

import '../../../core/network/api_client.dart';
import 'product_models.dart';

/// Admin product operations. Every call carries the in-memory credential.
class ProductsApi {
  const ProductsApi(this._api);

  final ApiClient _api;

  Future<ApiResult<List<AdminProduct>>> list(String token) => _api.getJson(
    '/api/v1/admin/products',
    (j) => decodeList(j, AdminProduct.fromJson),
    token: token,
  );

  Future<ApiResult<AdminProduct>> create(
    String token, {
    required String name,
    required String description,
    required int priceMinor,
  }) => _api.postJson(
    '/api/v1/admin/products',
    {'name': name, 'description': description, 'price_minor': priceMinor},
    AdminProduct.fromJson,
    token: token,
  );

  Future<ApiResult<AdminProduct>> update(
    String token,
    String id, {
    String? name,
    String? description,
    int? priceMinor,
    bool? available,
  }) => _api.patchJson(
    '/api/v1/admin/products/$id',
    {
      'name': ?name,
      'description': ?description,
      'price_minor': ?priceMinor,
      'available': ?available,
    },
    AdminProduct.fromJson,
    token: token,
  );

  Future<ApiResult<AdminProduct>> uploadImage(
    String token,
    String id,
    Uint8List bytes,
    String filename,
  ) => _api.uploadFile(
    '/api/v1/admin/products/$id/image',
    field: 'image',
    bytes: bytes,
    filename: filename,
    decode: AdminProduct.fromJson,
    token: token,
  );

  Future<ApiResult<AiSuggestion>> suggest(String token, String text) =>
      _api.postJson(
        '/api/v1/admin/ai/product-description',
        {'text': text},
        AiSuggestion.fromJson,
        token: token,
      );

  Uri? imageUri(String? path) => path == null ? null : _api.resolve(path);
}
