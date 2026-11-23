import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pusher_client/pusher_client.dart';
import 'package:pusher_client/src/auth.dart';
import 'package:pusher_client/src/platform/pusher_platform.dart';
import 'package:pusher_client/src/pusher_client.dart' as impl;

import 'helpers/fake_platform.dart';

void main() {
  late FakePlatform fake;

  setUp(() async {
    fake = await installFakePlatform();
  });

  tearDown(() async {
    await impl.PusherClient.resetForTesting();
    HttpAuthorizer.httpClientFactory = http.Client.new;
  });

  String idOf(FakePlatform f, [int initIndex = 0]) =>
      f.calls.where((c) => c.method == 'init').toList()[initIndex].args[0]
          as String;

  group('construction and call order', () {
    test('disposeAll, init, connect in order with protocol arguments',
        () async {
      PusherClient(
        'key',
        const PusherOptions(cluster: 'eu'),
        enableLogging: true,
      );
      await settle();
      expect(fake.methods, ['disposeAll', 'init', 'connect']);
      final init = fake.calls[1];
      expect(init.args[1], 'key');
      expect((init.args[2] as Map)['cluster'], 'eu');
      expect(init.args[3], isTrue);
      expect(fake.calls[2].args, [init.args[0]]);
    });

    test('autoConnect false does not connect', () async {
      PusherClient('key', const PusherOptions(), autoConnect: false);
      await settle();
      expect(fake.methods, ['disposeAll', 'init']);
    });

    test('disposeAll is sent once per isolate, not per client', () async {
      PusherClient('a', const PusherOptions(), autoConnect: false);
      PusherClient('b', const PusherOptions(), autoConnect: false);
      await settle();
      expect(fake.methods.where((m) => m == 'disposeAll'), hasLength(1));
      expect(fake.methods, ['disposeAll', 'init', 'init']);
      expect(idOf(fake, 0), isNot(idOf(fake, 1)));
    });

    test('later calls wait for a slow init', () async {
      fake.gates['init'] = Completer<void>();
      final client = PusherClient('k', const PusherOptions());
      client.subscribe('chan');
      final disconnect = client.disconnect();
      await settle();
      expect(fake.methods, ['disposeAll', 'init']);
      fake.gates['init']!.complete();
      await disconnect;
      expect(fake.methods, [
        'disposeAll',
        'init',
        'connect',
        'subscribe',
        'disconnect',
      ]);
    });

    test('defaults: logging off, state DISCONNECTED, no socket id', () async {
      final client = PusherClient('k', const PusherOptions());
      await settle();
      expect(fake.calls[1].args[3], isFalse);
      expect(client.connectionState, 'DISCONNECTED');
      expect(client.socketId, isNull);
      expect(client.getSocketId(), isNull);
      expect(client.appKey, 'k');
      expect(client.options.cluster, isNull);
    });

    test('instance ids are unique and non-singleton', () async {
      final a = PusherClient('k', const PusherOptions());
      final b = PusherClient('k', const PusherOptions());
      expect(identical(a, b), isFalse);
    });
  });

  group('host validation', () {
    for (final host in [
      'https://ws.example.com',
      'ws.example.com:6001',
      'a/b'
    ]) {
      test('rejects $host', () {
        expect(
          () => PusherClient('k', PusherOptions(host: host)),
          throwsArgumentError,
        );
      });
    }

    test('accepts a bare hostname and sends no native call on rejection',
        () async {
      expect(
        () => PusherClient('k', const PusherOptions(host: 'a://b')),
        throwsArgumentError,
      );
      PusherClient('k', const PusherOptions(host: 'ws.example.com'));
      await settle();
      expect(fake.methods.where((m) => m == 'init'), hasLength(1));
    });
  });

  group('connection state and errors', () {
    test('state events update state, socketId, callback and stream', () async {
      final client = PusherClient('k', const PusherOptions());
      await settle();
      final instanceId = idOf(fake);
      final callbackStates = <ConnectionStateChange>[];
      final streamStates = <ConnectionStateChange>[];
      client.onConnectionStateChange(callbackStates.add);
      client.connectionStateChanges.listen(streamStates.add);

      fake.emit({
        'instanceId': instanceId,
        'type': 'connectionStateChange',
        'currentState': 'CONNECTED',
        'previousState': 'CONNECTING',
        'socketId': '12.34',
      });
      await settle();
      expect(client.connectionState, 'CONNECTED');
      expect(client.socketId, '12.34');
      expect(client.getSocketId(), '12.34');
      const expected = ConnectionStateChange(
        currentState: 'CONNECTED',
        previousState: 'CONNECTING',
      );
      expect(callbackStates, [expected]);
      expect(streamStates, [expected]);

      fake.emit({
        'instanceId': instanceId,
        'type': 'connectionStateChange',
        'currentState': 'DISCONNECTED',
        'previousState': 'CONNECTED',
        'socketId': null,
      });
      await settle();
      expect(client.socketId, isNull);
      expect(client.connectionState, 'DISCONNECTED');
    });

    test('connection error events reach callback and stream', () async {
      final client = PusherClient('k', const PusherOptions());
      await settle();
      final fromCallback = <ConnectionError>[];
      final fromStream = <ConnectionError>[];
      client.onConnectionError(fromCallback.add);
      client.connectionErrors.listen(fromStream.add);
      fake.emit({
        'instanceId': idOf(fake),
        'type': 'connectionError',
        'message': 'bad',
        'code': '4001',
        'exception': 'ex',
      });
      await settle();
      const expected =
          ConnectionError(message: 'bad', code: '4001', exception: 'ex');
      expect(fromCallback, [expected]);
      expect(fromStream, [expected]);
    });

    test('callback exceptions do not break the stream', () async {
      final client = PusherClient('k', const PusherOptions());
      await settle();
      final streamStates = <ConnectionStateChange>[];
      client.onConnectionStateChange((_) => throw StateError('user bug'));
      client.onConnectionError((_) => throw StateError('user bug'));
      client.connectionStateChanges.listen(streamStates.add);
      final errors = <ConnectionError>[];
      client.connectionErrors.listen(errors.add);
      fake.emit({
        'instanceId': idOf(fake),
        'type': 'connectionStateChange',
        'currentState': 'CONNECTED',
      });
      fake.emit({'instanceId': idOf(fake), 'type': 'connectionError'});
      await settle();
      expect(streamStates, hasLength(1));
      expect(errors, hasLength(1));
    });

    test('init failure is reported, not thrown', () async {
      fake.failures['init'] =
          PlatformException(code: 'INIT_ERROR', message: 'cannot init');
      final client = PusherClient('k', const PusherOptions());
      final errors = <ConnectionError>[];
      client.onConnectionError(errors.add);
      await settle();
      expect(errors.first.code, 'INIT_ERROR');
      expect(errors.first.message, 'cannot init');
    });

    test('connect failure is reported and connect() does not throw', () async {
      fake.failures['connect'] =
          PlatformException(code: 'NO_INSTANCE', message: 'gone');
      final client =
          PusherClient('k', const PusherOptions(), autoConnect: false);
      final errors = <ConnectionError>[];
      client.connectionErrors.listen(errors.add);
      await client.connect();
      await settle();
      expect(errors.single.code, 'NO_INSTANCE');
    });

    test('non-platform failure and disposeAll failure are reported', () async {
      fake.failures['disposeAll'] = Exception('boom');
      final client =
          PusherClient('k', const PusherOptions(), autoConnect: false);
      final errors = <ConnectionError>[];
      client.onConnectionError(errors.add);
      await settle();
      expect(errors.single.message, contains('boom'));
      expect(errors.single.code, isNull);
      expect(fake.methods, contains('init'));
    });

    test('subscribe failure is reported', () async {
      fake.failures['subscribe'] =
          PlatformException(code: 'SUBSCRIBE_ERROR', message: 's');
      final client = PusherClient('k', const PusherOptions());
      final errors = <ConnectionError>[];
      client.onConnectionError(errors.add);
      client.subscribe('c');
      await settle();
      expect(errors.single.code, 'SUBSCRIBE_ERROR');
    });

    test('unknown instance, unknown type and bad events are ignored', () async {
      final client = PusherClient('k', const PusherOptions());
      await settle();
      fake.emit({'instanceId': 'nope', 'type': 'connectionError'});
      fake.emit({'type': 'connectionError'});
      fake.emit({'instanceId': idOf(fake), 'type': 'weird'});
      fake.emit({
        'instanceId': idOf(fake),
        'type': 'event',
        'channelName': 'not-subscribed',
        'eventName': 'e',
      });
      await settle();
      expect(client.connectionState, 'DISCONNECTED');
    });

    test('event stream errors are swallowed', () async {
      PusherClient('k', const PusherOptions());
      fake.controller.addError(StateError('x'));
      await settle();
    });

    test('logging enabled does not break dispatch', () async {
      final client =
          PusherClient('k', const PusherOptions(), enableLogging: true);
      await settle();
      fake.emit({'instanceId': idOf(fake), 'type': 'weird'});
      client.onConnectionStateChange((_) => throw StateError('x'));
      fake.emit({
        'instanceId': idOf(fake),
        'type': 'connectionStateChange',
        'currentState': 'CONNECTED',
      });
      await settle();
      expect(client.connectionState, 'CONNECTED');
    });
  });

  group('subscription retry', () {
    test('subscribe after pusher:subscription_error re-sends native subscribe',
        () async {
      final client = PusherClient('key', const PusherOptions());
      final first = client.subscribe('private-a');
      await settle();
      final id = idOf(fake);
      fake.emit({
        'instanceId': id,
        'type': 'event',
        'channelName': 'private-a',
        'eventName': 'pusher:subscription_error',
        'data': '{"type":"AuthError","error":"nope","status":403}',
      });
      await settle();
      expect(first.isSubscribed, isFalse);

      final again = client.subscribe('private-a');
      await settle();
      expect(identical(first, again), isTrue);
      expect(fake.methods.where((m) => m == 'subscribe'), hasLength(2));

      // A healthy channel is not re-subscribed.
      fake.emit({
        'instanceId': id,
        'type': 'event',
        'channelName': 'private-a',
        'eventName': 'pusher:subscription_succeeded',
        'data': '{}',
      });
      await settle();
      client.subscribe('private-a');
      await settle();
      expect(fake.methods.where((m) => m == 'subscribe'), hasLength(2));
      expect(again.isSubscribed, isTrue);
    });
  });

  group('multiple instances', () {
    test('events are routed by instanceId', () async {
      final a = PusherClient('a', const PusherOptions(), autoConnect: false);
      final b = PusherClient('b', const PusherOptions(), autoConnect: false);
      await settle();
      final idA = idOf(fake, 0);
      final idB = idOf(fake, 1);
      final ca = a.subscribe('chan');
      final cb = b.subscribe('chan');
      final gotA = <PusherEvent>[];
      final gotB = <PusherEvent>[];
      await ca.bind('e', gotA.add);
      await cb.bind('e', gotB.add);

      fake.emit({
        'instanceId': idA,
        'type': 'event',
        'channelName': 'chan',
        'eventName': 'e',
        'data': 'for-a',
      });
      fake.emit({
        'instanceId': idB,
        'type': 'event',
        'channelName': 'chan',
        'eventName': 'e',
        'data': 'for-b',
      });
      fake.emit({
        'instanceId': idB,
        'type': 'connectionStateChange',
        'currentState': 'CONNECTED',
        'socketId': 's',
      });
      await settle();
      expect(gotA.map((e) => e.data), ['for-a']);
      expect(gotB.map((e) => e.data), ['for-b']);
      expect(a.connectionState, 'DISCONNECTED');
      expect(b.connectionState, 'CONNECTED');
    });

    test('each client has its own authorizer / auth', () async {
      final a = PusherClient(
        'a',
        PusherOptions(
          authorizer: (c, s) async => PusherAuthorizationData(auth: 'a:$c'),
        ),
        autoConnect: false,
      );
      PusherClient(
        'b',
        PusherOptions(
          authorizer: (c, s) async => PusherAuthorizationData(auth: 'b:$c'),
        ),
        autoConnect: false,
      );
      await settle();
      expect(a.appKey, 'a');
      final ra = await fake.handler!(idOf(fake, 0), 'private-x', 's');
      final rb = await fake.handler!(idOf(fake, 1), 'private-x', 's');
      expect(ra['auth'], 'a:private-x');
      expect(rb['auth'], 'b:private-x');
    });
  });

  group('channels registry', () {
    test('subscribe returns same object, presence type, lookup, unmodifiable',
        () async {
      final client = PusherClient('k', const PusherOptions());
      final ch = client.subscribe('public');
      final pres = client.subscribe('presence-room');
      expect(client.subscribe('public'), same(ch));
      expect(pres, isA<PresenceChannel>());
      expect(ch, isNot(isA<PresenceChannel>()));
      expect(client.channel('public'), same(ch));
      expect(client.channel('nope'), isNull);
      expect(client.channels.keys, ['public', 'presence-room']);
      expect(() => client.channels['x'] = ch, throwsUnsupportedError);
      await settle();
      expect(fake.methods.where((m) => m == 'subscribe'), hasLength(2));
    });

    test('unsubscribe removes the channel and calls native once', () async {
      final client = PusherClient('k', const PusherOptions());
      final ch = client.subscribe('c');
      await settle();
      fake.emit({
        'instanceId': idOf(fake),
        'type': 'event',
        'channelName': 'c',
        'eventName': 'pusher:subscription_succeeded',
        'data': '{}',
      });
      await settle();
      expect(ch.isSubscribed, isTrue);
      await client.unsubscribe('c');
      expect(ch.isSubscribed, isFalse);
      expect(client.channel('c'), isNull);
      await client.unsubscribe('c');
      expect(fake.methods.where((m) => m == 'unsubscribe'), hasLength(1));
    });

    test('disconnect keeps subscriptions', () async {
      final client = PusherClient('k', const PusherOptions());
      client.subscribe('c');
      await client.disconnect();
      expect(client.channel('c'), isNotNull);
      expect(fake.methods.last, 'disconnect');
    });
  });

  group('authorization', () {
    Future<Map<String, Object?>> authorize(
      String channel, [
      int index = 0,
    ]) =>
        fake.handler!(idOf(fake, index), channel, '1.1');

    Future<PlatformException> authFailure(String channel) async {
      try {
        await authorize(channel);
      } on PlatformException catch (e) {
        return e;
      }
      fail('expected failure');
    }

    test('authorizer takes precedence over auth', () async {
      PusherClient(
        'k',
        PusherOptions(
          auth: const PusherAuth('https://never.example'),
          authorizer: (c, s) async => PusherAuthorizationData(
            auth: 'custom:$c:$s',
            sharedSecret: 'sec',
          ),
        ),
        autoConnect: false,
      );
      await settle();
      final r = await authorize('private-a');
      expect(r, {
        'auth': 'custom:private-a:1.1',
        'channel_data': null,
        'shared_secret': 'sec',
      });
    });

    test('HTTP auth is used and updateAuth replaces it', () async {
      final requests = <http.Request>[];
      HttpAuthorizer.httpClientFactory = () => MockClient((r) async {
            requests.add(r);
            return http.Response('{"auth":"k:sig"}', 200);
          });
      final client = PusherClient(
        'k',
        const PusherOptions(
          auth: PusherAuth('https://one.example/auth', headers: {'X': '1'}),
        ),
        autoConnect: false,
      );
      await settle();
      expect((await authorize('private-a'))['auth'], 'k:sig');
      client.updateAuth(
        const PusherAuth('https://two.example/auth', headers: {'X': '2'}),
      );
      await authorize('private-a');
      expect(requests.map((r) => r.url.host), ['one.example', 'two.example']);
      expect(requests.last.headers['X'], '2');
    });

    test('updateAuth enables HTTP auth when options had none', () async {
      HttpAuthorizer.httpClientFactory =
          () => MockClient((r) async => http.Response('{"auth":"z"}', 200));
      final client =
          PusherClient('k', const PusherOptions(), autoConnect: false);
      await settle();
      final e = await authFailure('private-a');
      expect(
        e.message,
        'No authorizer configured. Set PusherOptions.auth or '
        'PusherOptions.authorizer.',
      );
      expect(e.code, 'AUTH_ERROR');
      client.updateAuth(const PusherAuth('https://x.example'));
      expect((await authorize('private-a'))['auth'], 'z');
    });

    test('HTTP failure surfaces AUTH_ERROR with status', () async {
      HttpAuthorizer.httpClientFactory =
          () => MockClient((r) async => http.Response('nope', 401));
      PusherClient(
        'k',
        const PusherOptions(auth: PusherAuth('https://x.example')),
        autoConnect: false,
      );
      await settle();
      final e = await authFailure('private-a');
      expect(e.code, 'AUTH_ERROR');
      expect((e.details as Map)['status'], 401);
    });

    test('authorizer exceptions become AUTH_ERROR', () async {
      PusherClient(
        'k',
        PusherOptions(
            authorizer: (c, s) async => throw Exception('server down')),
        autoConnect: false,
      );
      await settle();
      final e = await authFailure('private-a');
      expect(e.code, 'AUTH_ERROR');
      expect(e.message, contains('server down'));
      expect((e.details as Map)['status'], isNull);
    });

    test('authorizer PusherException message is used', () async {
      PusherClient(
        'k',
        PusherOptions(
          authorizer: (c, s) async => throw const PusherException('nope'),
        ),
        autoConnect: false,
      );
      await settle();
      expect((await authFailure('private-a')).message, 'nope');
    });

    test('authorizer PlatformException is passed through', () async {
      PusherClient(
        'k',
        PusherOptions(
          authorizer: (c, s) async => throw PlatformException(
            code: 'AUTH_ERROR',
            message: 'm',
            details: {'status': 500},
          ),
        ),
        autoConnect: false,
      );
      await settle();
      expect(((await authFailure('private-a')).details as Map)['status'], 500);
    });

    test('unknown or disposed instance yields AUTH_ERROR', () async {
      final client = PusherClient(
        'k',
        PusherOptions(
          authorizer: (c, s) async => const PusherAuthorizationData(auth: 'a'),
        ),
        autoConnect: false,
      );
      await settle();
      final id = idOf(fake);
      await expectLater(
        fake.handler!('missing', 'c', 's'),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'AUTH_ERROR'),
        ),
      );
      await client.dispose();
      await expectLater(
        fake.handler!(id, 'c', 's'),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'AUTH_ERROR'),
        ),
      );
    });
  });

  group('dispose', () {
    test('sends dispose, then everything throws StateError', () async {
      final client = PusherClient('k', const PusherOptions());
      final ch = client.subscribe('private-x');
      await client.dispose();
      expect(fake.methods.last, 'dispose');
      expect(fake.calls.last.args, [idOf(fake)]);

      expect(() => client.subscribe('x'), throwsStateError);
      expect(() => client.channel('x'), throwsStateError);
      expect(() => client.channels, throwsStateError);
      expect(() => client.socketId, throwsStateError);
      expect(() => client.getSocketId(), throwsStateError);
      expect(() => client.connectionState, throwsStateError);
      expect(() => client.connectionStateChanges, throwsStateError);
      expect(() => client.connectionErrors, throwsStateError);
      expect(() => client.onConnectionError((_) {}), throwsStateError);
      expect(() => client.onConnectionStateChange((_) {}), throwsStateError);
      expect(
        () => client.updateAuth(const PusherAuth('https://x')),
        throwsStateError,
      );
      expect(client.connect(), throwsStateError);
      expect(client.disconnect(), throwsStateError);
      expect(client.unsubscribe('x'), throwsStateError);
      expect(ch.bind('e', (_) {}), throwsStateError);
      expect(ch.unbind('e'), throwsStateError);
      expect(() => ch.bindGlobal((_) {}), throwsStateError);
      expect(() => ch.unbindGlobal(), throwsStateError);
      expect(ch.trigger('e', 'd'), throwsStateError);
    });

    test('dispose is idempotent and events afterwards are ignored', () async {
      final client = PusherClient('k', const PusherOptions());
      await settle();
      final id = idOf(fake);
      await client.dispose();
      await client.dispose();
      expect(fake.methods.where((m) => m == 'dispose'), hasLength(1));
      fake.emit({'instanceId': id, 'type': 'connectionError'});
      await settle();
    });

    test('dispose waits for init and survives a native failure', () async {
      fake.gates['init'] = Completer<void>();
      fake.failures['dispose'] =
          PlatformException(code: 'NO_INSTANCE', message: 'x');
      final client =
          PusherClient('k', const PusherOptions(), autoConnect: false);
      final done = client.dispose();
      await settle();
      expect(fake.methods, ['disposeAll', 'init']);
      fake.gates['init']!.complete();
      await done;
      expect(fake.methods.last, 'dispose');
    });

    test('disposing one client leaves others working', () async {
      final a = PusherClient('a', const PusherOptions(), autoConnect: false);
      final b = PusherClient('b', const PusherOptions(), autoConnect: false);
      await settle();
      final idB = idOf(fake, 1);
      await a.dispose();
      fake.emit({
        'instanceId': idB,
        'type': 'connectionStateChange',
        'currentState': 'CONNECTED',
      });
      await settle();
      expect(b.connectionState, 'CONNECTED');
    });
  });

  test('PusherPlatform.instance can be swapped', () {
    expect(PusherPlatform.instance, same(fake));
  });
}
