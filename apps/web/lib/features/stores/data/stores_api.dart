import '../../../core/network/api_client.dart';
import 'store_models.dart';

class StoresApi {
  const StoresApi(this._api);

  final ApiClient _api;

  Future<ApiResult<CreatedStore>> create({
    required String name,
    required String whatsapp,
    required String description,
  }) => _api.postJson('/api/v1/stores', {
    'name': name,
    'whatsapp': whatsapp,
    'description': description,
  }, CreatedStore.fromJson);

  Future<ApiResult<CurrentStore>> current(String token) => _api.getJson(
    '/api/v1/admin/stores/current',
    CurrentStore.fromJson,
    token: token,
  );

  Future<ApiResult<PublicStore>> publicStore(String slug) => _api.getJson(
    '/api/v1/stores/${Uri.encodeComponent(slug)}',
    PublicStore.fromJson,
  );
}
