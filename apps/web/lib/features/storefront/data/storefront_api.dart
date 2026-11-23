import '../../../core/network/api_client.dart';
import 'storefront_models.dart';

/// Server-priced test payment (MockPaymentGateway; never real money).
class TestPayment {
  const TestPayment({
    required this.id,
    required this.status,
    required this.amountMinor,
    required this.notice,
  });
  factory TestPayment.fromJson(Map<String, dynamic> j) => TestPayment(
    id: j['id'] as String,
    status: j['status'] as String,
    amountMinor: j['amount_minor'] as int,
    notice: j['notice'] as String? ?? '',
  );
  final String id, status, notice;
  final int amountMinor;
  bool get approved => status == 'test_approved';
  bool get declined => status == 'test_declined';
}

/// Public storefront + test checkout.
class StorefrontApi {
  const StorefrontApi(this._api);
  final ApiClient _api;

  Future<ApiResult<StorefrontView>> load(String slug) => _api.getJson(
    '/api/v1/public/stores/${Uri.encodeComponent(slug)}/storefront',
    StorefrontView.fromJson,
  );

  Future<ApiResult<TestPayment>> checkout(
    String slug,
    Map<String, int> quantities,
    String idempotencyKey,
  ) => _api.postJson(
    '/api/v1/public/stores/${Uri.encodeComponent(slug)}/checkout',
    {
      'items': [
        for (final e in quantities.entries)
          {'product_id': e.key, 'quantity': e.value},
      ],
      'idempotency_key': idempotencyKey,
    },
    TestPayment.fromJson,
  );

  Future<ApiResult<TestPayment>> simulate(
    String paymentId,
    String outcome,
  ) => _api.postJson(
    '/api/v1/public/payments/${Uri.encodeComponent(paymentId)}/test-outcome',
    {'outcome': outcome},
    TestPayment.fromJson,
  );

  Uri? imageUri(String? path) => path == null ? null : _api.resolve(path);
}
