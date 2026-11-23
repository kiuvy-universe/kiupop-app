import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiupop/app.dart';
import 'package:kiupop/app_services.dart';
import 'package:kiupop/core/auth/auth_gateway.dart';
import 'package:kiupop/core/network/api_client.dart';
import 'package:kiupop/core/platform/platform_actions.dart';
import 'package:kiupop/features/voice/data/voice_io.dart';

/// Records side effects instead of opening real tabs.
class FakePlatform {
  final opened = <Uri>[];
  final copied = <String>[];
  PickedImage? nextImage;
  List<PickedFile> nextFiles = const [];
  void Function(String text, bool isFinal)? dictate; // set while dictating

  PlatformActions get actions => PlatformActions(
    openUrl: (uri) async {
      opened.add(uri);
      return true;
    },
    copyText: (t) async => copied.add(t),
    pickImage: () async => nextImage,
    pickFiles: () async => nextFiles,
    dictationAvailable: () => true,
    startDictation:
        ({required lang, required onText, required onEnd, required onError}) {
          dictate = onText;
          return _FakeDictation(onEnd);
        },
  );
}

/// In-memory fake of the KiuPop API (shapes match packages/api_contracts).
class FakeApi {
  FakeApi({this.aiEnabled = false, this.offline = false});

  bool aiEnabled;
  bool offline;
  final requests = <http.Request>[];
  final products = <Map<String, dynamic>>[];
  String token = 'kp_test_token_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  Map<String, dynamic> store = {
    'id': '6f1d2c3b-4a59-4e8f-9a0b-1c2d3e4f5a6b',
    'slug': 'flores-de-occidente',
    'name': 'Flores de Occidente',
    'description': 'Flores frescas.',
    'whatsapp': '50600000001',
  };

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  bool _authed(http.Request r) => r.headers['Authorization'] == 'Bearer $token';

  // KPOP-WOW-001: voice notes and funnel.
  bool speechEnabled = false;
  String transcript =
      'Soy Dulce Luna, vendo queques de naranja a 6500 y galletas a 2500.';
  int? speechFailStatus;
  String speechFailCode = 'speech_failed';
  final transcribedBytes = <int>[];
  final funnelEvents = <Map<String, dynamic>>[];

  /// When set, attachment uploads wait for it (to test cancel and progress).
  Completer<void>? holdUploads;
  int uploadFailures = 0;

  late final client = MockClient((r) async {
    requests.add(r);
    if (offline) throw http.ClientException('offline');
    final path = r.url.path;
    if (path.startsWith('/api/v1/speech/') || path == '/api/v1/funnel/events') {
      if (r.headers['Authorization'] != 'Bearer $idToken') {
        return _json({
          'error': {'code': 'unauthorized', 'message': 'Iniciá sesión.'},
        }, 401);
      }
      if (path == '/api/v1/funnel/events') {
        funnelEvents.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response('', 204);
      }
      if (path == '/api/v1/speech/status') {
        return _json({
          'enabled': speechEnabled,
          'provider': speechEnabled ? 'google-stt-v1' : 'disabled',
          'max_seconds': 60,
          'max_bytes': 4194304,
        });
      }
      transcribedBytes.add(r.bodyBytes.length);
      if (speechFailStatus != null) {
        return _json({
          'error': {
            'code': speechFailCode,
            'message': 'No te escuché. Probá de nuevo.',
          },
        }, speechFailStatus!);
      }
      return _json({
        'text': transcript,
        'provider': 'google-stt-v1',
        'language': 'es-cr',
        'confidence': 0.9,
        'duration_ms': 3000,
        'latency_ms': 900,
        'billed_seconds': 3,
      });
    }
    if (path.endsWith('/attachments') && r.method == 'POST') {
      final hold = holdUploads;
      if (hold != null) await hold.future;
      if (uploadFailures > 0) {
        uploadFailures--;
        return _json({
          'error': {
            'code': 'internal_error',
            'message': 'Se cortó la conexión.',
          },
        }, 500);
      }
    }
    Map<String, dynamic> body = {};
    final multipart =
        r.headers['content-type']?.startsWith('multipart/') ?? false;
    if (!multipart && r.body.isNotEmpty) {
      body = jsonDecode(r.body) as Map<String, dynamic>;
    }
    if (r.method == 'POST' && path == '/api/v1/stores') {
      final name = body['name'] as String;
      if (name.trim().length < 2) {
        return _json({
          'error': {
            'code': 'validation_failed',
            'message': 'x',
            'fields': {'name': 'Nombre inválido (servidor).'},
          },
        }, 422);
      }
      store = {...store, 'name': name};
      return _json({
        'store': store,
        'admin_token': token,
        'public_path': '/s/${store['slug']}',
        'features': {'ai': aiEnabled},
      }, 201);
    }
    if (path.startsWith('/api/v1/admin/') && !_authed(r)) {
      return _json({
        'error': {
          'code': 'unauthorized',
          'message': 'La clave de administrador no es válida.',
        },
      }, 401);
    }
    if (r.method == 'GET' && path == '/api/v1/admin/stores/current') {
      return _json({
        'store': store,
        'features': {'ai': aiEnabled},
      });
    }
    if (r.method == 'GET' && path == '/api/v1/admin/products') {
      return _json({'data': products});
    }
    if (r.method == 'POST' && path == '/api/v1/admin/products') {
      final p = {
        'id': _id(products.length + 1),
        'name': body['name'],
        'description': body['description'] ?? '',
        'price_minor': body['price_minor'],
        'currency': 'CRC',
        'image_url': null,
        'available': true,
        'created_at': '2026-11-22T15:04:05Z',
      };
      products.add(p);
      return _json(p, 201);
    }
    if (r.method == 'POST' && path == '/api/v1/admin/ai/product-description') {
      if (!aiEnabled) {
        return _json({
          'error': {
            'code': 'ai_disabled',
            'message': 'KiuPop AI no está disponible.',
          },
        }, 503);
      }
      return _json({
        'name': 'Rosa roja natural',
        'short_description': 'Una rosa fresca, ideal para regalar.',
        'marketing_text': '',
        'generated_by': 'KiuPop AI',
      });
    }
    if (r.method == 'GET' && path == '/api/v1/stores/${store['slug']}') {
      return _json({
        'slug': store['slug'],
        'name': store['name'],
        'description': store['description'],
      });
    }
    if (r.method == 'GET' &&
        path == '/api/v1/public/stores/${store['slug']}/products') {
      return _json({
        'data': [
          for (final p in products.where((p) => p['available'] == true))
            {
              for (final k in [
                'id',
                'name',
                'description',
                'price_minor',
                'currency',
                'image_url',
              ])
                k: p[k],
            },
        ],
      });
    }
    if (r.method == 'POST' &&
        path == '/api/v1/public/stores/${store['slug']}/orders/preview') {
      var total = 0;
      for (final it in (body['items'] as List).cast<Map<String, dynamic>>()) {
        final p = products.firstWhere((p) => p['id'] == it['product_id']);
        total += (p['price_minor'] as int) * (it['quantity'] as int);
      }
      return _json({
        'store': {'slug': store['slug'], 'name': store['name']},
        'lines': <Object>[],
        'total_minor': total,
        'currency': 'CRC',
        'message': 'Hola',
        'whatsapp_url': 'https://wa.me/50600000001?text=Hola',
      });
    }
    if (path.startsWith('/api/v1/agent/') || path == '/api/v1/me') {
      if (r.headers['Authorization'] != 'Bearer $idToken') {
        return _json({
          'error': {'code': 'unauthorized', 'message': 'Iniciá sesión.'},
        }, 401);
      }
      return kiu.handle(r.method, path, body, _json, r.url.queryParameters);
    }
    if (r.method == 'GET' &&
        path == '/api/v1/public/stores/${store['slug']}/storefront') {
      return _json(storefront(status: 'published'));
    }
    if (r.method == 'POST' &&
        path == '/api/v1/public/stores/${store['slug']}/checkout') {
      if (checkoutFailures > 0) {
        checkoutFailures--;
        return _json({
          'error': {
            'code': 'temporary',
            'message': 'El checkout no está disponible.',
          },
        }, 503);
      }
      var total = 0;
      for (final it in (body['items'] as List).cast<Map<String, dynamic>>()) {
        final p = products.firstWhere((p) => p['id'] == it['product_id']);
        total += (p['price_minor'] as int) * (it['quantity'] as int);
      }
      payment = {..._payment, 'amount_minor': total, 'status': 'pending'};
      return _json(payment!, 201);
    }
    if (r.method == 'POST' && path.endsWith('/test-outcome')) {
      payment = {
        ...payment!,
        'status': body['outcome'] == 'approved'
            ? 'test_approved'
            : 'test_declined',
      };
      return _json(payment!);
    }
    if (path.startsWith('/api/v1/stores/') ||
        path.startsWith('/api/v1/public/stores/')) {
      return _json({
        'error': {
          'code': 'store_not_found',
          'message': 'No encontramos esta tienda.',
        },
      }, 404);
    }
    return _json({
      'error': {'code': 'not_found', 'message': 'x'},
    }, 404);
  });

  static const idToken = 'fake.id.token-for-tests';
  bool testCheckout = false;
  int checkoutFailures = 0;
  Map<String, dynamic>? payment;
  static const _payment = {
    'id': '99999999-1111-4111-8111-111111111111',
    'status': 'pending',
    'mode': 'test',
    'gateway': 'mock',
    'amount_minor': 0,
    'currency': 'CRC',
    'lines': <Object>[],
    'notice': 'Pago de prueba: no se cobra dinero real.',
  };
  late final kiu = FakeKiu(this);

  /// Public storefront built from the shared contract example's theme.
  Map<String, dynamic> storefront({
    required String status,
    String template = 'bubblegum_pink',
  }) {
    final ex = contractExample('storefront_view.json');
    final theme = Map<String, dynamic>.from(ex['theme'] as Map)
      ..['template'] = template;
    return {
      ...ex,
      'theme': theme,
      'store': {
        ...(ex['store'] as Map<String, dynamic>),
        'slug': store['slug'],
        'name': store['name'],
        'status': status,
      },
      'products': [
        for (final p in products.where((p) => p['available'] == true))
          {
            'id': p['id'],
            'name': p['name'],
            'description': p['description'],
            'price_minor': p['price_minor'],
            'currency': 'CRC',
            'image_url': null,
            'featured': false,
          },
      ],
      'payments': {
        'checkout': testCheckout ? 'test' : 'none',
        'real_payments_enabled': false,
        'methods_to_coordinate': <String>[],
      },
    };
  }

  void addProduct(String name, int priceMinor, {bool available = true}) {
    products.add({
      'id': _id(products.length + 1),
      'name': name,
      'description': 'Producto de prueba.',
      'price_minor': priceMinor,
      'currency': 'CRC',
      'image_url': null,
      'available': available,
      'created_at': '2026-11-22T15:04:05Z',
    });
  }
}

AppServices servicesFor(
  FakeApi api,
  FakePlatform platform, {
  AuthGateway? auth,
  VoiceIO? voice,
}) => AppServices(
  api: ApiClient(baseUrl: Uri.parse('http://api.test'), httpClient: api.client),
  platform: platform.actions,
  publicBase: Uri.parse('http://localhost:3000/'),
  auth: auth ?? FakeAuth(),
  voice: voice ?? FakeVoice().io,
);

/// Microphone and player fakes: the test feeds PCM chunks by hand.
class FakeVoice {
  bool permission = true;
  bool startFails = false;
  StreamController<Uint8List>? mic;
  final levels = StreamController<double>.broadcast();
  final played = <int>[];
  final playing = StreamController<bool>.broadcast();

  VoiceIO get io => VoiceIO(
    recorder: () => _FakeRecorder(this),
    preview: () => _FakePreview(this),
  );

  /// Speaks [seconds] of a loud 16 kHz tone into the microphone.
  void speak(double seconds) {
    final n = (seconds * 16000).round();
    final pcm = ByteData(n * 2);
    for (var i = 0; i < n; i++) {
      pcm.setInt16(i * 2, (i % 40 < 20) ? 6000 : -6000, Endian.little);
    }
    mic!.add(pcm.buffer.asUint8List());
  }
}

class _FakeRecorder implements VoiceRecorder {
  _FakeRecorder(this.v);
  final FakeVoice v;
  @override
  Future<bool> hasPermission() async => v.permission;
  @override
  Future<Stream<Uint8List>> start() async {
    if (v.startFails) throw StateError('no mic');
    v.mic = StreamController<Uint8List>();
    return v.mic!.stream;
  }

  @override
  Future<void> stop() async {
    unawaited(v.mic?.close());
  }

  @override
  Stream<double> level() => v.levels.stream;
  @override
  Future<void> dispose() async {}
}

class _FakePreview implements AudioPreview {
  _FakePreview(this.v);
  final FakeVoice v;
  @override
  Future<void> play(Uint8List wav) async {
    v.played.add(wav.length);
    v.playing.add(true);
  }

  @override
  Future<void> stop() async => v.playing.add(false);
  @override
  Stream<bool> get playing => v.playing.stream;
  @override
  Future<void> dispose() async {}
}

/// In-memory auth gateway. Tokens it hands out are accepted by [FakeApi].
class FakeAuth extends AuthGateway {
  FakeAuth({bool signedIn = false, this.facebook = false})
    : _user = signedIn
          ? const AuthUser(uid: 'u1', email: 'ana@example.test')
          : null;

  AuthUser? _user;
  final bool facebook;
  final calls = <String>[];

  @override
  AuthUser? get currentUser => _user;
  @override
  String get mode => 'emulator';
  @override
  bool get googleEnabled => true;
  @override
  bool get facebookEnabled => facebook;
  @override
  Future<void> get ready async {}
  @override
  Future<String?> idToken({bool force = false}) async =>
      _user == null ? null : FakeApi.idToken;

  void _in(String how) {
    calls.add(how);
    _user = const AuthUser(uid: 'u1', email: 'ana@example.test');
    notifyListeners();
  }

  @override
  Future<void> signInWithGoogle({String? testEmail, String? testName}) async =>
      _in('google');
  @override
  Future<void> signInWithFacebook() async {
    if (!facebook) throw const AuthException(AuthFailure.providerDisabled);
    _in('facebook');
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    if (password != 'secreto123') {
      throw const AuthException(AuthFailure.invalidCredentials);
    }
    _in('email');
  }

  @override
  Future<void> registerWithEmail(String email, String password) async =>
      _in('register');
  @override
  Future<void> signOut() async {
    _user = null;
    notifyListeners();
  }
}

Future<void> pumpApp(
  WidgetTester tester,
  AppServices services, {
  String at = '/',
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(KiuPopApp(services: services, initialLocation: at));
  await tester.pumpAndSettle();
}

Uint8List tinyPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

String _id(int n) =>
    '${n.toString().padLeft(8, '0')}-1111-4111-8111-111111111111';

Map<String, dynamic> contractExample(String name) => jsonDecode(
  File('../../packages/api_contracts/examples/$name').readAsStringSync(),
) as Map<String, dynamic>;

/// Scripted Kiu backend: description → prices → WhatsApp → ready → publish.
class FakeKiu {
  FakeKiu(this.api);
  final FakeApi api;
  bool exists = false;
  String status = 'collecting';
  int turn = 0;
  int eventId = 10;
  final messages = <Map<String, dynamic>>[];
  final events = <Map<String, dynamic>>[];
  Map<String, dynamic>? pending;
  bool published = false;
  int publishCalls = 0;
  int readinessReadFailures = 0;
  final files = <Map<String, dynamic>>[];

  void _kiu(
    String text, {
    Map<String, dynamic>? question,
    List<Map<String, String>>? replies,
    String kind = 'ack',
  }) {
    messages.add({
      'id': messages.length + 1,
      'role': 'kiu',
      'text': text,
      'meta': {
        'kind': kind,
        'question': ?question,
        'quick_replies': ?replies,
        'brain_mode': 'local',
      },
      'created_at': '2026-11-22T15:00:00Z',
    });
  }

  void _event(String type) => events.add({
    'id': ++eventId,
    'type': type,
    'payload': <String, Object>{},
    'created_at': '2026-11-22T15:00:00Z',
  });

  int get _percent => switch (status) {
    'ready' || 'published' => 100,
    _ => turn == 0 ? 0 : 40 + turn * 15,
  };

  Map<String, dynamic> session() => {
    'id': '0b1c2d3e-4f5a-4b6c-8d7e-8f9a0b1c2d3e',
    'status': status,
    'revision': turn + 1,
    'store': {'slug': api.store['slug']},
    'messages': messages,
    'pending_question': pending,
    'progress': {
      'percent': _percent,
      'ready': status == 'ready' || status == 'published',
      'tasks': [
        {
          'key': 'profile',
          'label': 'Entender tu negocio',
          'status': turn > 0 ? 'done' : 'pending',
        },
        {
          'key': 'catalog',
          'label': 'Armar el catálogo',
          'status': turn > 1 ? 'done' : 'needs_input',
        },
        {
          'key': 'copy',
          'label': 'Descripciones (requiere IA)',
          'status': 'skipped',
        },
      ],
    },
    'readiness': {
      'ready': status == 'ready' || status == 'published',
      'missing': <Object>[],
    },
    'summary': {
      'business_name': 'Florería Bella',
      'template': 'bubblegum_pink',
      'template_reason': '',
    },
    'ai': {'mode': 'local', 'calls': 0, 'cost_micros': 0},
    'last_event_id': eventId,
    'timing': {'first_message_to_ready_ms': null},
    'publication': published
        ? {
            'slug': api.store['slug'],
            'version': 1,
            'public_path': '/s/${api.store['slug']}',
            'share_url': 'http://localhost:8080/p/${api.store['slug']}',
          }
        : null,
    'attachments': files,
    'limits': {
      'max_attachments': 5,
      'max_attachments_bytes': 52428800,
      'attachments_enabled': true,
    },
  };

  http.Response handle(
    String method,
    String path,
    Map<String, dynamic> body,
    http.Response Function(Object, [int]) json,
    Map<String, String> query,
  ) {
    if (method == 'GET' && path == '/api/v1/agent/sessions/current') {
      if (!exists) {
        return json({
          'error': {'code': 'session_not_found', 'message': 'x'},
        }, 404);
      }
      return json(session());
    }
    if (method == 'POST' && path == '/api/v1/agent/sessions') {
      if (!exists) {
        exists = true;
        _kiu('¡Hola! Soy Kiu. Contame qué hace tu negocio.', kind: 'greeting');
      }
      return json(session());
    }
    final id = '/api/v1/agent/sessions/0b1c2d3e-4f5a-4b6c-8d7e-8f9a0b1c2d3e';
    if (method == 'GET' && path == id) {
      if (status == 'ready' && readinessReadFailures > 0) {
        readinessReadFailures--;
        return json({
          'error': {
            'code': 'temporary',
            'message': 'El estado no está disponible.',
          },
        }, 503);
      }
      return json(session());
    }
    if (method == 'POST' && path == '$id/messages') {
      messages.add({
        'id': messages.length + 1,
        'role': 'user',
        'text': body['text'],
        'meta': <String, Object>{},
        'created_at': '2026-11-22T15:00:00Z',
      });
      turn++;
      switch (turn) {
        case 1:
          _kiu('¡Qué lindo, Florería Bella! Ya empecé a armar tu tienda.');
          pending = {
            'field': 'prices',
            'text': '¿Cuánto cuestan tus productos?',
            'reason': 'Nunca invento precios.',
            'essential': true,
            'quick_replies': null,
          };
          _kiu(pending!['text'] as String, question: pending, kind: 'question');
        case 2:
          pending = {
            'field': 'delivery',
            'text': '¿Entregás a domicilio, retiran o ambas?',
            'reason': 'Para no inventar condiciones.',
            'essential': false,
            'quick_replies': [
              {'label': 'Ambas', 'value': 'Ambas opciones'},
              {'label': 'Omitir', 'value': 'omitir'},
            ],
          };
          _kiu(pending!['text'] as String, question: pending, kind: 'question');
        default:
          pending = null;
          status = 'building';
          _kiu(
            '¡Ya tengo todo lo que necesito! Estoy terminando tu tienda…',
            kind: 'building',
          );
          // The worker finishes asynchronously: the next event poll delivers POP.
          _event('preview.updated');
          _event('store.ready');
      }
      return json(session());
    }
    if (method == 'GET' && path == '$id/events') {
      final after = int.parse(query['after'] ?? '0');
      final out = events.where((e) => (e['id'] as int) > after).toList();
      if (out.any((e) => e['type'] == 'store.ready') && status == 'building') {
        status = 'ready';
        _kiu(
          '¡POP! Tu tienda está lista.',
          kind: 'ready',
          replies: [
            {'label': 'Publicar mi tienda', 'value': '__publish__'},
            {'label': 'Probar Mint Fresh', 'value': 'Probar Mint Fresh'},
          ],
        );
      }
      return json({'events': out});
    }
    if (method == 'POST' && path == '$id/attachments') {
      final f = {
        'id': '${files.length + 1}'.padLeft(8, '0'),
        'kind': 'image',
        'filename': 'ramo.png',
        'size_bytes': 68,
        'status': 'processed',
        'note': 'Foto de «Ramo de rosas».',
        'image_url': null,
        'created_at': '2026-11-22T15:00:00Z',
      };
      files.add(f);
      return json(f, 201);
    }
    if (method == 'POST' && path == '$id/attachments') {
      final f = {
        'id': '${files.length + 1}'.padLeft(8, '0'),
        'kind': 'image',
        'filename': 'ramo.png',
        'size_bytes': 68,
        'status': 'processed',
        'note': 'Foto de «Ramo de rosas».',
        'image_url': null,
        'created_at': '2026-11-22T15:00:00Z',
      };
      files.add(f);
      return json(f, 201);
    }
    if (method == 'POST' && path == '$id/stream-ticket') {
      return json({'ticket': 't', 'expires_in': 600});
    }
    if (method == 'GET' && path == '$id/preview') {
      return json(api.storefront(status: published ? 'published' : 'draft'));
    }
    if (method == 'POST' && path == '$id/publish') {
      publishCalls++;
      if (body['confirm'] != true) {
        return json({
          'error': {'code': 'confirmation_required', 'message': 'x'},
        }, 400);
      }
      published = true;
      status = 'published';
      _kiu('¡Tu tienda ya está publicada!', kind: 'published');
      _event('store.published');
      return json({
        'slug': api.store['slug'],
        'version': 1,
        'public_path': '/s/${api.store['slug']}',
        'share_url': 'http://localhost:8080/p/${api.store['slug']}',
      });
    }
    return json({
      'error': {'code': 'not_found', 'message': 'x'},
    }, 404);
  }
}

/// Scrolls [f] into view, taps it and settles.
Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

class _FakeDictation implements Dictation {
  _FakeDictation(this._end);
  final void Function() _end;
  @override
  void stop() => _end();
}

/// A fresh conversation starts with "¿Cómo querés contarle tu idea a Kiu?":
/// tests that type choose "Escribir mi idea" first (no-op afterwards).
Future<void> chooseWriting(WidgetTester tester) async {
  final writing = find.byKey(const Key('intake-text'));
  if (writing.evaluate().isNotEmpty) {
    await tapVisible(tester, writing);
  }
}
