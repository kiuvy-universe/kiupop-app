import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiupop/core/auth/auth_gateway.dart';
import 'package:kiupop/core/auth/emulator_auth_gateway.dart';

void main() {
  test(
    'emulator gateway: register, refresh, wrong password, sign out',
    () async {
      final seen = <String>[];
      var refreshes = 0;
      final client = MockClient((r) async {
        seen.add(r.url.host + r.url.path);
        expect(r.url.host, 'localhost', reason: 'never talks to Google');
        http.Response ok(Object b) => http.Response(jsonEncode(b), 200);
        if (r.url.path.endsWith('accounts:signUp')) {
          return ok({
            'idToken': 'tok-1',
            'refreshToken': 'rt-1',
            'localId': 'u1',
            'email': 'ana@kiupop.test',
            'expiresIn': '3600',
          });
        }
        if (r.url.path.endsWith('accounts:signInWithPassword')) {
          return http.Response(
            jsonEncode({
              'error': {'message': 'INVALID_LOGIN_CREDENTIALS'},
            }),
            400,
          );
        }
        if (r.url.path.endsWith('/token')) {
          refreshes++;
          return ok({
            'id_token': 'tok-2',
            'refresh_token': 'rt-2',
            'expires_in': '3600',
            'user_id': 'u1',
          });
        }
        return http.Response('{}', 404);
      });
      final g = EmulatorAuthGateway(host: 'localhost:9199', client: client);
      await g.registerWithEmail('ana@kiupop.test', 'secreto123');
      expect(g.currentUser?.uid, 'u1');
      expect(await g.idToken(), 'tok-1');
      expect(await g.idToken(force: true), 'tok-2');
      expect(refreshes, 1);
      expect(
        () => g.signInWithEmail('ana@kiupop.test', 'mala'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.invalidCredentials,
          ),
        ),
      );
      // A new instance restores the session from local storage.
      final again = EmulatorAuthGateway(host: 'localhost:9199', client: client);
      expect(again.currentUser?.uid, 'u1');
      await again.signOut();
      expect(again.currentUser, isNull);
      expect(await again.idToken(), isNull);
    },
  );
}
