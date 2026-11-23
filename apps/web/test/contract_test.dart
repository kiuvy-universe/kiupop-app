import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiupop/core/format/money.dart';
import 'package:kiupop/core/network/api_client.dart';
import 'package:kiupop/features/catalog/data/catalog_api.dart';
import 'package:kiupop/features/products/data/product_models.dart';
import 'package:kiupop/features/stores/data/store_models.dart';

/// The same example payloads the Go contract test uses.
Map<String, dynamic> _example(String name) => jsonDecode(
  File('../../packages/api_contracts/examples/$name').readAsStringSync(),
) as Map<String, dynamic>;

void main() {
  test('Dart models parse every shared contract example', () {
    final created = CreatedStore.fromJson(
      _example('store_create_response.json'),
    );
    expect(created.store.slug, 'flores-de-occidente');
    expect(created.adminToken, startsWith('kp_'));
    expect(
      PublicStore.fromJson(_example('store_public.json')).name,
      'Flores de Occidente',
    );
    expect(
      CurrentStore.fromJson(_example('admin_store_current.json')).aiEnabled,
      isTrue,
    );
    expect(
      AdminProduct.fromJson(_example('product_admin.json')).priceMinor,
      200000,
    );
    expect(
      decodeList(
        _example('products_admin_list.json'),
        AdminProduct.fromJson,
      ).single.imageUrl,
      isNull,
    );
    expect(
      decodeList(
        _example('products_public_list.json'),
        PublicProduct.fromJson,
      ).single.currency,
      'CRC',
    );
    final preview = OrderPreview.fromJson(
      _example('order_preview_response.json'),
    );
    expect(preview.totalMinor, 700000);
    expect(preview.whatsappUrl.host, 'wa.me');
    expect(preview.whatsappUrl.queryParameters['text'], preview.message);
    expect(
      AiSuggestion.fromJson(_example('ai_response.json')).name,
      'Rosa roja natural',
    );
  });

  test(
    'ApiClient maps error envelopes, validation fields and bad payloads',
    () async {
      final client = ApiClient(
        baseUrl: Uri.parse('http://api.test'),
        httpClient: MockClient(
          (req) async => switch (req.url.path) {
            '/down' => http.Response(
              jsonEncode({
                'error': {
                  'code': 'database_unavailable',
                  'message': 'Sin base.',
                },
              }),
              503,
            ),
            '/invalid' => http.Response(
              jsonEncode({
                'error': {
                  'code': 'validation_failed',
                  'message': 'Revisa',
                  'fields': {'name': 'Muy corto'},
                },
              }),
              422,
            ),
            _ => http.Response('not json', 200),
          },
        ),
      );
      final down = await client.getJson(
        '/down',
        PublicStore.fromJson,
      ) as ApiFailure<PublicStore>;
      expect(down.code, 'database_unavailable');
      expect(down.message, 'Sin base.');
      final invalid = await client.postJson(
        '/invalid',
        {},
        PublicStore.fromJson,
      ) as ApiFailure<PublicStore>;
      expect(invalid.fields, {'name': 'Muy corto'});
      final bad = await client.getJson(
        '/bad',
        PublicStore.fromJson,
      ) as ApiFailure<PublicStore>;
      expect(bad.kind, ApiFailureKind.badResponse);
    },
  );

  test('Money formats and parses colones without floats', () {
    expect(Money.crc(200000), '₡2.000');
    expect(Money.crc(123456789), '₡1.234.567,89');
    expect(Money.crc(0), '₡0');
    expect(Money.parseColones('2.000'), 200000);
    expect(Money.parseColones('₡ 2 000'), 200000);
    expect(Money.parseColones('0'), isNull);
    expect(Money.parseColones('12,5'), isNull);
    expect(Money.parseColones('abc'), isNull);
    expect(Money.parseColones('1000000001'), isNull);
    expect(Money.editable(200000), '2000');
  });
}
