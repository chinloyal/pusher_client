import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pusher_client/pusher_client.dart';
import 'package:pusher_client/src/auth.dart';
import 'package:pusher_client/src/options.dart' as src;

void main() {
  late http.Request captured;
  late bool closed;

  void useClient(http.Response Function(http.Request) respond) {
    HttpAuthorizer.httpClientFactory = () {
      closed = false;
      return _ClosingClient(MockClient((request) async {
        captured = request;
        return respond(request);
      }), () => closed = true);
    };
  }

  tearDown(() => HttpAuthorizer.httpClientFactory = http.Client.new);

  group('PusherAuthorizationData', () {
    test('fromJson maps keys', () {
      final d = PusherAuthorizationData.fromJson({
        'auth': 'k:s',
        'channel_data': '{"user_id":1}',
        'shared_secret': 'sec',
      });
      expect(d.auth, 'k:s');
      expect(d.channelData, '{"user_id":1}');
      expect(d.sharedSecret, 'sec');
      expect(d.toMap(), {
        'auth': 'k:s',
        'channel_data': '{"user_id":1}',
        'shared_secret': 'sec',
      });
    });

    test('fromJson encodes object channel_data and requires auth', () {
      final d = PusherAuthorizationData.fromJson({
        'auth': 'a',
        'channel_data': {'user_id': 1},
      });
      expect(d.channelData, '{"user_id":1}');
      expect(d.sharedSecret, isNull);
      expect(() => PusherAuthorizationData.fromJson({}), throwsFormatException);
    });
  });

  group('PusherAuth', () {
    test('defaults', () {
      const a = PusherAuth('https://x');
      expect(a.headers, isEmpty);
      expect(a.params, isEmpty);
    });
  });

  group('PusherOptions', () {
    test('defaults', () {
      const o = PusherOptions();
      expect(o.wsPort, 80);
      expect(o.wssPort, 443);
      expect(o.encrypted, isTrue);
      expect(o.activityTimeout, 120000);
      expect(o.pongTimeout, 30000);
      expect(o.maxReconnectionAttempts, 6);
      expect(o.maxReconnectGapInSeconds, 30);
      expect(o.host, isNull);
      expect(o.cluster, isNull);
    });

    test('toMap matches the protocol', () {
      const o = src.PusherOptions(
        cluster: 'eu',
        host: 'h.example',
        wsPort: 1,
        wssPort: 2,
        encrypted: false,
        activityTimeout: 3,
        pongTimeout: 4,
        maxReconnectionAttempts: 5,
        maxReconnectGapInSeconds: 6,
        auth: PusherAuth('https://x'),
      );
      expect(o.toMap(), {
        'cluster': 'eu',
        'host': 'h.example',
        'wsPort': 1,
        'wssPort': 2,
        'useTLS': false,
        'activityTimeout': 3,
        'pongTimeout': 4,
        'maxReconnectionAttempts': 5,
        'maxReconnectGapInSeconds': 6,
        'hasAuthorizer': true,
      });
      expect(const PusherOptions().toMap()['hasAuthorizer'], isFalse);
      expect(
        PusherOptions(
          authorizer: (c, s) async => const PusherAuthorizationData(auth: 'a'),
        ).toMap()['hasAuthorizer'],
        isTrue,
      );
    });
  });

  group('HttpAuthorizer', () {
    test('posts form-urlencoded by default', () async {
      useClient((_) => http.Response(
            jsonEncode({'auth': 'k:s', 'channel_data': '{"user_id":"1"}'}),
            200,
          ));
      final data = await HttpAuthorizer.authorize(
        const PusherAuth(
          'https://example.com/auth',
          headers: {'Authorization': 'Bearer t'},
          params: {'extra': 'a b'},
        ),
        'private-x',
        '1.2',
      );
      expect(data.auth, 'k:s');
      expect(data.channelData, '{"user_id":"1"}');
      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://example.com/auth');
      expect(captured.headers['Authorization'], 'Bearer t');
      expect(captured.headers['content-type'],
          startsWith('application/x-www-form-urlencoded'));
      expect(Uri.splitQueryString(captured.body), {
        'extra': 'a b',
        'socket_id': '1.2',
        'channel_name': 'private-x',
      });
      expect(closed, isTrue);
    });

    test('posts JSON when a json content-type header (any case) is set',
        () async {
      useClient((_) => http.Response('{"auth":"a"}', 200));
      await HttpAuthorizer.authorize(
        const PusherAuth(
          'https://example.com/auth',
          headers: {'CONTENT-TYPE': 'Application/JSON; charset=utf-8'},
          params: {'p': 'v'},
        ),
        'presence-x',
        '9.9',
      );
      expect(jsonDecode(captured.body), {
        'p': 'v',
        'socket_id': '9.9',
        'channel_name': 'presence-x',
      });
    });

    test('keeps a non-json custom content-type with a form body', () async {
      useClient((_) => http.Response('{"auth":"a"}', 200));
      await HttpAuthorizer.authorize(
        const PusherAuth('https://e.com',
            headers: {'Content-Type': 'text/plain'}),
        'private-x',
        '1.1',
      );
      expect(captured.headers['content-type'], startsWith('text/plain'));
      expect(captured.body, contains('socket_id=1.1'));
    });

    Future<PlatformException> failure(http.Response r) async {
      useClient((_) => r);
      try {
        await HttpAuthorizer.authorize(
            const PusherAuth('https://e.com'), 'p', 's');
      } on PlatformException catch (e) {
        return e;
      }
      fail('expected PlatformException');
    }

    test('non-2xx yields AUTH_ERROR with status and truncated body', () async {
      final e = await failure(http.Response('x' * 800, 403));
      expect(e.code, 'AUTH_ERROR');
      expect((e.details as Map)['status'], 403);
      expect(e.message, contains('403'));
      expect(e.message, contains('x' * 500));
      expect(e.message, isNot(contains('x' * 501)));
      expect(closed, isTrue);
    });

    test('short error body is included verbatim', () async {
      final e = await failure(http.Response('Forbidden', 401));
      expect(e.message, contains('Forbidden'));
    });

    test('invalid JSON, non-object and missing auth yield AUTH_ERROR',
        () async {
      for (final body in ['not json', '[1]', '{"nope":1}']) {
        final e = await failure(http.Response(body, 200));
        expect(e.code, 'AUTH_ERROR', reason: body);
        expect((e.details as Map)['status'], 200);
      }
    });

    test('network errors yield AUTH_ERROR without status', () async {
      HttpAuthorizer.httpClientFactory =
          () => MockClient((_) async => throw http.ClientException('offline'));
      try {
        await HttpAuthorizer.authorize(
            const PusherAuth('https://e.com'), 'p', 's');
        fail('expected throw');
      } on PlatformException catch (e) {
        expect(e.code, 'AUTH_ERROR');
        expect((e.details as Map)['status'], isNull);
        expect(e.message, contains('offline'));
      }
    });
  });
}

class _ClosingClient extends http.BaseClient {
  _ClosingClient(this._inner, this._onClose);
  final http.Client _inner;
  final void Function() _onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    _onClose();
    _inner.close();
  }
}
