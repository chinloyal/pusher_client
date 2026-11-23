import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_client/src/platform/method_channel_platform.dart';
import 'package:pusher_client/src/platform/pusher_platform.dart';

const _methodName = 'com.github.chinloyal/pusher_client';
const _eventName = 'com.github.chinloyal/pusher_client_stream';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelPusherPlatform platform;
  late List<MethodCall> calls;
  Object? Function(MethodCall)? respond;

  setUp(() {
    platform = MethodChannelPusherPlatform();
    calls = [];
    respond = null;
    messenger.setMockMethodCallHandler(const MethodChannel(_methodName), (
      call,
    ) async {
      calls.add(call);
      return respond?.call(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel(_methodName), null);
    messenger.setMockStreamHandler(const EventChannel(_eventName), null);
  });

  test('default instance is the method channel platform', () {
    expect(PusherPlatform.instance, isA<MethodChannelPusherPlatform>());
  });

  test('sends exact argument maps', () async {
    await platform.disposeAll();
    await platform.init('i-1', 'key', {'cluster': 'eu'}, true);
    await platform.connect('i-1');
    await platform.disconnect('i-1');
    await platform.subscribe('i-1', 'ch');
    await platform.unsubscribe('i-1', 'ch');
    await platform.trigger('i-1', 'private-ch', 'client-e', '{"a":1}');
    respond = (_) => '1.2';
    expect(await platform.getSocketId('i-1'), '1.2');
    await platform.dispose('i-1');

    expect(calls.map((c) => c.method), [
      'disposeAll',
      'init',
      'connect',
      'disconnect',
      'subscribe',
      'unsubscribe',
      'trigger',
      'getSocketId',
      'dispose',
    ]);
    expect(calls[0].arguments, <String, Object?>{});
    expect(calls[1].arguments, {
      'instanceId': 'i-1',
      'appKey': 'key',
      'enableLogging': true,
      'options': {'cluster': 'eu'},
    });
    expect(calls[2].arguments, {'instanceId': 'i-1'});
    expect(calls[3].arguments, {'instanceId': 'i-1'});
    expect(calls[4].arguments, {'instanceId': 'i-1', 'channelName': 'ch'});
    expect(calls[5].arguments, {'instanceId': 'i-1', 'channelName': 'ch'});
    expect(calls[6].arguments, {
      'instanceId': 'i-1',
      'channelName': 'private-ch',
      'eventName': 'client-e',
      'data': '{"a":1}',
    });
    expect(calls[7].arguments, {'instanceId': 'i-1'});
    expect(calls[8].arguments, {'instanceId': 'i-1'});
  });

  test('propagates native PlatformException', () async {
    respond = (_) => throw PlatformException(code: 'INIT_ERROR', message: 'm');
    expect(
      platform.init('i', 'k', {}, false),
      throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'INIT_ERROR')),
    );
  });

  group('events', () {
    late int listens;
    late int cancels;
    late MockStreamHandlerEventSink? sink;

    setUp(() {
      listens = 0;
      cancels = 0;
      sink = null;
      messenger.setMockStreamHandler(
        const EventChannel(_eventName),
        MockStreamHandler.inline(
          onListen: (args, events) {
            listens++;
            sink = events;
          },
          onCancel: (args) => cancels++,
        ),
      );
    });

    test('uses ONE native subscription for many listeners and converts maps',
        () async {
      final a = <Map<String, Object?>>[];
      final b = <Map<String, Object?>>[];
      final s1 = platform.events.listen(a.add);
      final s2 = platform.events.listen(b.add);
      await Future<void>.delayed(Duration.zero);
      expect(listens, 1);

      sink!.success(<Object?, Object?>{
        'instanceId': 'i',
        'type': 'event',
        'nested': <Object?, Object?>{'k': 1},
        'list': <Object?>[
          <Object?, Object?>{'x': 2},
        ],
      });
      sink!.success('not a map');
      sink!.success(null);
      await Future<void>.delayed(Duration.zero);

      expect(a, hasLength(1));
      expect(b, hasLength(1));
      expect(a.single, {
        'instanceId': 'i',
        'type': 'event',
        'nested': {'k': 1},
        'list': [
          {'x': 2},
        ],
      });
      expect(a.single, isA<Map<String, Object?>>());
      expect(a.single['nested'], isA<Map<String, Object?>>());
      await s1.cancel();
      await s2.cancel();
      expect(cancels, 1);
    });

    test('events getter returns the same stream', () {
      expect(identical(platform.events, platform.events), isTrue);
    });
  });

  group('authorize round trip', () {
    Future<Object?> invokeFromNative(Object? arguments,
        [String method = 'authorize']) {
      final completer = Completer<ByteData?>();
      messenger.handlePlatformMessage(
        _methodName,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, arguments)),
        completer.complete,
      );
      return completer.future.then((data) {
        return const StandardMethodCodec().decodeEnvelope(data!);
      });
    }

    test('returns the handler result', () async {
      String? seen;
      platform.authorizeHandler = (id, ch, sock) async {
        seen = '$id|$ch|$sock';
        return {'auth': 'k:s', 'channel_data': null, 'shared_secret': null};
      };
      final result = await invokeFromNative(
        <Object?, Object?>{
          'instanceId': 'i',
          'channelName': 'private-c',
          'socketId': '1.2'
        },
      );
      expect(seen, 'i|private-c|1.2');
      expect(
          result, {'auth': 'k:s', 'channel_data': null, 'shared_secret': null});
    });

    test('handler PlatformException is passed through', () async {
      platform.authorizeHandler = (a, b, c) async => throw PlatformException(
            code: 'AUTH_ERROR',
            message: 'denied',
            details: {'status': 403},
          );
      await expectLater(
        invokeFromNative(
            {'instanceId': 'i', 'channelName': 'c', 'socketId': 's'}),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'AUTH_ERROR')
              .having((e) => e.details, 'details', {'status': 403}),
        ),
      );
    });

    test('other handler errors become AUTH_ERROR', () async {
      platform.authorizeHandler = (a, b, c) async => throw StateError('bad');
      await expectLater(
        invokeFromNative(
            {'instanceId': 'i', 'channelName': 'c', 'socketId': 's'}),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'AUTH_ERROR')
              .having((e) => e.message, 'message', contains('bad'))
              .having((e) => e.details, 'details', {'status': null}),
        ),
      );
    });

    test('invalid arguments become AUTH_ERROR', () async {
      platform.authorizeHandler = (a, b, c) async => {'auth': 'x'};
      for (final args in <Object?>[
        null,
        'str',
        {'instanceId': 'i'},
        {'instanceId': 1, 'channelName': 'c', 'socketId': 's'},
      ]) {
        await expectLater(
          invokeFromNative(args),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'AUTH_ERROR')),
        );
      }
    });

    test('unknown methods are answered as not implemented', () async {
      platform.authorizeHandler = (a, b, c) async => {};
      final completer = Completer<ByteData?>();
      messenger.handlePlatformMessage(
        _methodName,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('bogus')),
        completer.complete,
      );
      expect(await completer.future, isNull);
    });
  });
}
