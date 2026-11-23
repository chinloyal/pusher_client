import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_client/pusher_client.dart';
import 'package:pusher_client/src/pusher_client.dart' as impl;

import 'helpers/fake_platform.dart';

void main() {
  late FakePlatform fake;
  late PusherClient client;
  late String instanceId;

  setUp(() async {
    fake = await installFakePlatform();
    client = PusherClient(
        'k',
        PusherOptions(
          authorizer: (c, s) async => PusherAuthorizationData(
            auth: 'a',
            channelData: c.startsWith('presence-')
                ? jsonEncode({
                    'user_id': 42,
                    'user_info': {'n': 'me'}
                  })
                : null,
          ),
        ));
    await settle();
    instanceId =
        fake.calls.firstWhere((c) => c.method == 'init').args[0] as String;
    fake.calls.clear();
  });

  tearDown(() => impl.PusherClient.resetForTesting());

  Future<void> emit(
    String channel,
    String event, {
    String? data,
    String? userId,
  }) async {
    fake.emit({
      'instanceId': instanceId,
      'type': 'event',
      'channelName': channel,
      'eventName': event,
      'data': data,
      'userId': userId,
    });
    await settle();
  }

  Future<void> succeed(String channel, [String data = '{}']) =>
      emit(channel, 'pusher:subscription_succeeded', data: data);

  group('bind / unbind / bindGlobal', () {
    test('bind routes only matching events and makes no native call', () async {
      final ch = client.subscribe('c');
      await settle();
      fake.calls.clear();
      final got = <PusherEvent>[];
      await ch.bind('hello', got.add);
      await emit('c', 'hello', data: 'x', userId: 'u');
      await emit('c', 'other', data: 'y');
      expect(got, [
        const PusherEvent(
          channelName: 'c',
          eventName: 'hello',
          data: 'x',
          userId: 'u',
        ),
      ]);
      expect(fake.calls, isEmpty);
    });

    test('bind replaces the callback for the same event', () async {
      final ch = client.subscribe('c');
      final first = <PusherEvent>[];
      final second = <PusherEvent>[];
      await ch.bind('e', first.add);
      await ch.bind('e', second.add);
      await emit('c', 'e');
      expect(first, isEmpty);
      expect(second, hasLength(1));
    });

    test('unbind removes only that event', () async {
      final ch = client.subscribe('c');
      final a = <PusherEvent>[];
      final b = <PusherEvent>[];
      await ch.bind('a', a.add);
      await ch.bind('b', b.add);
      await ch.unbind('a');
      await emit('c', 'a');
      await emit('c', 'b');
      expect(a, isEmpty);
      expect(b, hasLength(1));
    });

    test('bindGlobal receives everything, replaces, and unbindGlobal stops',
        () async {
      final ch = client.subscribe('c');
      final first = <PusherEvent>[];
      final second = <PusherEvent>[];
      ch.bindGlobal(first.add);
      ch.bindGlobal(second.add);
      await emit('c', 'x');
      await emit('c', 'pusher:subscription_succeeded', data: '{}');
      expect(first, isEmpty);
      expect(second.map((e) => e.eventName),
          ['x', 'pusher:subscription_succeeded']);
      ch.unbindGlobal();
      await emit('c', 'y');
      expect(second, hasLength(2));
    });

    test(
        'specific and global callbacks both fire; throwing one does not block the other',
        () async {
      final ch = client.subscribe('c');
      final got = <String>[];
      await ch.bind('e', (_) => throw StateError('specific'));
      ch.bindGlobal((e) => got.add('global:${e.eventName}'));
      await emit('c', 'e');
      expect(got, ['global:e']);
    });

    test('throwing callbacks are logged when logging is enabled', () async {
      final loud =
          PusherClient('k', const PusherOptions(), enableLogging: true);
      await settle();
      final id = fake.calls.where((c) => c.method == 'init').last.args[0];
      final ch = loud.subscribe('c');
      await ch.bind('e', (_) => throw StateError('x'));
      fake.emit({
        'instanceId': id,
        'type': 'event',
        'channelName': 'c',
        'eventName': 'e',
      });
      await settle();
    });

    test('callback may unbind itself during dispatch', () async {
      final ch = client.subscribe('c');
      var calls = 0;
      await ch.bind('e', (_) {
        calls++;
        ch.unbind('e');
      });
      await emit('c', 'e');
      await emit('c', 'e');
      expect(calls, 1);
    });

    test('events only reach their own channel', () async {
      final a = client.subscribe('a');
      final b = client.subscribe('b');
      final gotA = <PusherEvent>[];
      final gotB = <PusherEvent>[];
      a.bindGlobal(gotA.add);
      b.bindGlobal(gotB.add);
      await emit('a', 'e');
      expect(gotA, hasLength(1));
      expect(gotB, isEmpty);
    });
  });

  group('subscription state', () {
    test('isSubscribed lifecycle', () async {
      final ch = client.subscribe('c');
      expect(ch.isSubscribed, isFalse);
      await succeed('c');
      expect(ch.isSubscribed, isTrue);
      await emit('c', 'pusher:subscription_error',
          data: '{"type":"AuthError","error":"x","status":403}');
      expect(ch.isSubscribed, isFalse);
      await succeed('c');
      expect(ch.isSubscribed, isTrue);
      await client.unsubscribe('c');
      expect(ch.isSubscribed, isFalse);
    });

    test('subscriptionCount tracks pusher:subscription_count', () async {
      final ch = client.subscribe('c');
      expect(ch.subscriptionCount, isNull);
      await emit('c', 'pusher:subscription_count',
          data: '{"subscription_count":7}');
      expect(ch.subscriptionCount, 7);
      await emit('c', 'pusher:subscription_count', data: 'garbage');
      expect(ch.subscriptionCount, 7);
      await emit('c', 'pusher:subscription_count', data: null);
      expect(ch.subscriptionCount, 7);
      await client.unsubscribe('c');
      expect(ch.subscriptionCount, isNull);
    });
  });

  group('trigger', () {
    Future<void> expectTriggerError(Future<void> f) => expectLater(
          f,
          throwsA(
            isA<PusherException>()
                .having((e) => e.code, 'code', 'TRIGGER_ERROR'),
          ),
        );

    test('rejects public, private-encrypted channels without calling native',
        () async {
      for (final name in ['public', 'private-encrypted-x']) {
        final ch = client.subscribe(name);
        await succeed(name);
        await expectTriggerError(ch.trigger('e', 'd'));
      }
      expect(fake.methods.where((m) => m == 'trigger'), isEmpty);
    });

    test('rejects when not yet subscribed', () async {
      final ch = client.subscribe('private-x');
      await expectTriggerError(ch.trigger('e', 'd'));
      await succeed('private-x');
      await emit('private-x', 'pusher:subscription_error', data: '{}');
      await expectTriggerError(ch.trigger('e', 'd'));
      expect(fake.methods.where((m) => m == 'trigger'), isEmpty);
    });

    test('prefixes client-, sends strings as-is and JSON-encodes the rest',
        () async {
      final ch = client.subscribe('private-x');
      await succeed('private-x');
      await ch.trigger('one', 'plain text');
      await ch.trigger('client-two', {'a': 1});
      await ch.trigger('three', [1, 2]);
      await ch.trigger('four', 5);
      await ch.trigger('five', null);
      final triggers = fake.calls.where((c) => c.method == 'trigger').toList();
      expect(triggers.map((c) => c.args.sublist(1)), [
        ['private-x', 'client-one', 'plain text'],
        ['private-x', 'client-two', '{"a":1}'],
        ['private-x', 'client-three', '[1,2]'],
        ['private-x', 'client-four', '5'],
        ['private-x', 'client-five', 'null'],
      ]);
      expect(triggers.first.args[0], instanceId);
    });

    test('presence channels may trigger', () async {
      final ch = client.subscribe('presence-x');
      await succeed(
          'presence-x', '{"presence":{"count":0,"ids":[],"hash":{}}}');
      await ch.trigger('e', 'd');
      expect(fake.methods, contains('trigger'));
    });

    test('unencodable data throws TRIGGER_ERROR', () async {
      final ch = client.subscribe('private-x');
      await succeed('private-x');
      await expectTriggerError(ch.trigger('e', Object()));
    });

    test('native trigger failure propagates as PlatformException', () async {
      fake.failures['trigger'] =
          PlatformException(code: 'TRIGGER_ERROR', message: 'n');
      final ch = client.subscribe('private-x');
      await succeed('private-x');
      await expectLater(
          ch.trigger('e', 'd'), throwsA(isA<PlatformException>()));
    });
  });

  group('PresenceChannel', () {
    const presenceData = '{"presence":{"count":2,"ids":["1","2"],'
        '"hash":{"1":{"name":"A"},"2":null}}}';

    PresenceChannel presence() =>
        client.subscribe('presence-room') as PresenceChannel;

    test('members from subscription_succeeded', () async {
      final ch = presence();
      expect(ch.members, isEmpty);
      expect(ch.memberCount, 0);
      await succeed('presence-room', presenceData);
      expect(ch.members, {
        '1': {'name': 'A'},
        '2': null
      });
      expect(ch.memberCount, 2);
      expect(() => ch.members['x'] = 1, throwsUnsupportedError);
    });

    test('member_added and member_removed', () async {
      final ch = presence();
      await succeed('presence-room', presenceData);
      await emit('presence-room', 'pusher:member_added',
          data: '{"user_id":"3","user_info":{"name":"C"}}', userId: '3');
      expect(ch.members['3'], {'name': 'C'});
      expect(ch.memberCount, 3);
      await emit('presence-room', 'pusher:member_added',
          data: '{"user_id":4,"user_info":null}');
      expect(ch.members.containsKey('4'), isTrue);
      await emit('presence-room', 'pusher:member_removed',
          data: '{"user_id":"1"}', userId: '1');
      expect(ch.members.containsKey('1'), isFalse);
      await emit('presence-room', 'pusher:member_removed',
          data: null, userId: '2');
      expect(ch.members.keys.toSet(), {'3', '4'});
    });

    test('member events with no usable id are ignored', () async {
      final ch = presence();
      await emit('presence-room', 'pusher:member_added', data: 'nope');
      await emit('presence-room', 'pusher:member_removed', data: 'nope');
      expect(ch.members, isEmpty);
    });

    test('resubscribe replaces the member list', () async {
      final ch = presence();
      await succeed('presence-room', presenceData);
      await succeed('presence-room',
          '{"presence":{"count":1,"ids":["9"],"hash":{"9":null}}}');
      expect(ch.members.keys, ['9']);
      await succeed('presence-room', '{}');
      expect(ch.members, isEmpty);
    });

    test('members cleared on subscription_error and unsubscribe', () async {
      final ch = presence();
      await succeed('presence-room', presenceData);
      await emit('presence-room', 'pusher:subscription_error', data: '{}');
      expect(ch.members, isEmpty);
      await succeed('presence-room', presenceData);
      await client.unsubscribe('presence-room');
      expect(ch.members, isEmpty);
      expect(ch.me, isNull);
    });

    test('me comes from the auth channel_data (numeric id)', () async {
      final ch = presence();
      expect(ch.me, isNull);
      await fake.handler!(instanceId, 'presence-room', '1.1');
      expect(ch.me, '42');
    });

    test('me handles string ids and ignores missing / invalid channel_data',
        () async {
      final other = PusherClient(
        'k2',
        PusherOptions(authorizer: (c, s) async {
          switch (c) {
            case 'presence-a':
              return const PusherAuthorizationData(
                  auth: 'a', channelData: '{"user_id":"abc"}');
            case 'presence-b':
              return const PusherAuthorizationData(
                  auth: 'a', channelData: 'not json');
            default:
              return const PusherAuthorizationData(auth: 'a');
          }
        }),
        autoConnect: false,
      );
      await settle();
      final id =
          fake.calls.where((c) => c.method == 'init').last.args[0] as String;
      final a = other.subscribe('presence-a') as PresenceChannel;
      final b = other.subscribe('presence-b') as PresenceChannel;
      final c = other.subscribe('presence-c') as PresenceChannel;
      for (final n in ['presence-a', 'presence-b', 'presence-c']) {
        await fake.handler!(id, n, '1.1');
      }
      expect(a.me, 'abc');
      expect(b.me, isNull);
      expect(c.me, isNull);
    });

    test('authorizing a channel that is no longer subscribed still succeeds',
        () async {
      final r = await fake.handler!(instanceId, 'presence-gone', '1.1');
      expect(r['auth'], 'a');
    });

    test('bind works for presence events', () async {
      final ch = presence();
      final got = <PusherEvent>[];
      await ch.bind('pusher:member_added', got.add);
      await emit('presence-room', 'pusher:member_added',
          data: '{"user_id":"3","user_info":null}', userId: '3');
      expect(got.single.userId, '3');
    });
  });
}
