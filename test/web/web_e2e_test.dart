// Browser end-to-end test: the web implementation with REAL pusher-js (loaded
// from the CDN by the plugin itself) against a real Pusher-protocol server.
//
// Skipped unless `--dart-define=PUSHER_E2E=true` is passed. Requires soketi on
// 127.0.0.1:6001 (app id `app-id`, key `app-key`, secret `app-secret`, client
// messages enabled) and internet access to js.pusher.com. Run with:
//
//   flutter test --platform chrome --dart-define=PUSHER_E2E=true \
//       test/web/web_e2e_test.dart
//
// Channel authorization signatures are computed with the browser's WebCrypto
// (HMAC-SHA256), so no extra dependency is needed.
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_client/pusher_client.dart';
import 'package:pusher_client/src/platform/pusher_platform.dart';
import 'package:pusher_client/src/web/web_pusher_platform.dart';
import 'package:web/web.dart' as web;

const bool _e2e = bool.fromEnvironment('PUSHER_E2E');
const String _key = 'app-key';
const String _secret = 'app-secret';
const Duration _timeout = Duration(seconds: 15);

Future<String> _hmacHex(String secret, String message) async {
  final subtle = web.window.crypto.subtle;
  final key = await subtle
      .importKey(
        'raw',
        Uint8List.fromList(utf8.encode(secret)).toJS,
        {'name': 'HMAC', 'hash': 'SHA-256'}.jsify()! as JSObject,
        false,
        ['sign'.toJS].toJS,
      )
      .toDart;
  final sig = await subtle
      .sign(
        'HMAC'.toJS as JSAny,
        key,
        Uint8List.fromList(utf8.encode(message)).toJS,
      )
      .toDart;
  return (sig as JSArrayBuffer)
      .toDart
      .asUint8List()
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

Future<PusherAuthorizationData> _sign(
  String channel,
  String socketId, {
  String? channelData,
}) async {
  final toSign = channelData == null
      ? '$socketId:$channel'
      : '$socketId:$channel:$channelData';
  return PusherAuthorizationData(
    auth: '$_key:${await _hmacHex(_secret, toSign)}',
    channelData: channelData,
  );
}

PusherAuthorizer _authorizer([String? userId, String? name]) =>
    (channel, socketId) => _sign(
          channel,
          socketId,
          channelData: channel.startsWith('presence-')
              ? jsonEncode({
                  'user_id': userId,
                  'user_info': {'name': name},
                })
              : null,
        );

PusherOptions _options(PusherAuthorizer? authorizer) => PusherOptions(
      host: '127.0.0.1',
      wsPort: 6001,
      encrypted: false,
      authorizer: authorizer,
    );

int _n = 0;
String _unique() => '${DateTime.now().millisecondsSinceEpoch}${_n++}';

Future<void> _until(bool Function() cond, String what) async {
  final end = DateTime.now().add(_timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out after ${_timeout.inSeconds}s waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

class _Rec {
  _Rec(Channel channel) {
    channel.bindGlobal(events.add);
  }
  final List<PusherEvent> events = [];
  List<PusherEvent> named(String n) =>
      events.where((e) => e.eventName == n).toList();
  Future<PusherEvent> waitFor(String n, [int count = 1]) async {
    await _until(() => named(n).length >= count, '"$n" event ($events)');
    return named(n)[count - 1];
  }
}

void main() {
  final clients = <PusherClient>[];

  PusherClient make(PusherAuthorizer? authorizer) {
    final c = PusherClient(_key, _options(authorizer));
    clients.add(c);
    return c;
  }

  setUpAll(() {
    // No fake pusher-js: the plugin injects the real script from the CDN.
    PusherPlatform.instance = WebPusherPlatform();
  });

  tearDown(() async {
    for (final c in clients) {
      await c.dispose();
    }
    clients.clear();
  });

  group('web e2e (real pusher-js + soketi)', () {
    test('connect then disconnect', () async {
      final c = make(null);
      await _until(() => c.connectionState == 'CONNECTED', 'CONNECTED');
      expect(c.socketId, isNotNull);
      await c.disconnect();
      await _until(() => c.connectionState == 'DISCONNECTED', 'DISCONNECTED');
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('public channel subscription', () async {
      final c = make(null);
      final ch = c.subscribe('test-public-${_unique()}');
      final rec = _Rec(ch);
      final e = await rec.waitFor('pusher:subscription_succeeded');
      expect(e.data, '{}');
      expect(ch.isSubscribed, isTrue);
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('private channel with a locally signing authorizer', () async {
      final c = make(_authorizer());
      final ch = c.subscribe('private-e2e-${_unique()}');
      await _Rec(ch).waitFor('pusher:subscription_succeeded');
      expect(ch.isSubscribed, isTrue);
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('client event between two clients', () async {
      final name = 'private-e2e-${_unique()}';
      final a = make(_authorizer());
      final b = make(_authorizer());
      final chA = a.subscribe(name);
      final chB = b.subscribe(name);
      final recA = _Rec(chA);
      final recB = _Rec(chB);
      await recA.waitFor('pusher:subscription_succeeded');
      await recB.waitFor('pusher:subscription_succeeded');
      await chA.trigger('client-ping', {'n': 1, 'msg': 'hi'});
      final e = await recB.waitFor('client-ping');
      expect(jsonDecode(e.data!), {'n': 1, 'msg': 'hi'});
      expect(recA.named('client-ping'), isEmpty);
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('presence channel members', () async {
      final name = 'presence-e2e-${_unique()}';
      final a = make(_authorizer('u1', 'A'));
      final chA = a.subscribe(name) as PresenceChannel;
      final recA = _Rec(chA);
      final subA = await recA.waitFor('pusher:subscription_succeeded');
      expect(chA.me, 'u1');
      expect(chA.memberCount, 1);
      expect(chA.members, {
        'u1': {'name': 'A'},
      });
      expect(jsonDecode(subA.data!)['presence']['count'], 1);

      final b = make(_authorizer('u2', 'B'));
      final chB = b.subscribe(name) as PresenceChannel;
      final recB = _Rec(chB);
      await recB.waitFor('pusher:subscription_succeeded');
      expect(chB.me, 'u2');
      expect(chB.memberCount, 2);
      expect(chB.members, {
        'u1': {'name': 'A'},
        'u2': {'name': 'B'},
      });

      final added = await recA.waitFor('pusher:member_added');
      expect(added.userId, 'u2');
      expect(jsonDecode(added.data!), {
        'user_id': 'u2',
        'user_info': {'name': 'B'},
      });
      expect(chA.memberCount, 2);
      expect(chA.members.keys, containsAll(['u1', 'u2']));

      await b.unsubscribe(name);
      final removed = await recA.waitFor('pusher:member_removed');
      expect(removed.userId, 'u2');
      expect(jsonDecode(removed.data!), {'user_id': 'u2'});
      await _until(() => chA.memberCount == 1, 'memberCount 1');
      expect(chA.members.keys, ['u1']);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('authorizer failure delivers pusher:subscription_error', () async {
      final c = make((channel, socketId) async => throw StateError('nope'));
      final ch = c.subscribe('private-e2e-${_unique()}');
      final rec = _Rec(ch);
      final e = await rec.waitFor('pusher:subscription_error');
      final data = jsonDecode(e.data!) as Map;
      expect(data['type'], 'AuthError');
      expect(data['error'], contains('nope'));
      expect(ch.isSubscribed, isFalse);
    }, timeout: const Timeout(Duration(seconds: 40)));
  }, skip: _e2e ? false : 'Pass --dart-define=PUSHER_E2E=true to run.');
}
