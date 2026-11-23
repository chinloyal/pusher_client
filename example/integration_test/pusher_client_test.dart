// End-to-end tests against a real Pusher-protocol server (soketi). See
// integration_test/README.md for how to run them.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pinenacl/x25519.dart' show SecretBox;
import 'package:pusher_client/pusher_client.dart';

import 'support.dart';

/// Android, iOS and macOS report the sender's user id on presence client events.
final bool platformReportsClientEventUserId =
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

PusherAuthorizer userAuthorizer(String userId, [Object? info]) =>
    (channel, socketId) async => authData(
          socketId,
          channel,
          userId: channel.startsWith('presence-') ? userId : null,
          userInfo: channel.startsWith('presence-')
              ? (info ?? {'name': 'User $userId'})
              : null,
        );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('connection', () {
    testWidgets('connect, disconnect and reconnect', (tester) async {
      final t = TestClient(testOptions());
      await t.waitConnected();
      await waitUntil(() => t.streamStates.contains('CONNECTED'),
          'CONNECTED on the stream (${t.streamStates})');
      expect(t.client.connectionState, 'CONNECTED');
      expect(t.client.socketId, isNotNull);
      expect(t.client.getSocketId(), t.client.socketId);

      await t.client.disconnect();
      await waitUntil(() => t.client.connectionState == 'DISCONNECTED',
          'DISCONNECTED (${t.callbackStates})');
      expect(t.callbackStates, contains('DISCONNECTED'));
      expect(t.streamStates, contains('DISCONNECTED'));
      expect(t.client.socketId, isNull);

      await t.client.connect();
      await waitUntil(
          () =>
              t.client.connectionState == 'CONNECTED' &&
              t.client.socketId != null,
          'reconnected (${t.callbackStates})');
    });

    testWidgets('autoConnect false waits for connect()', (tester) async {
      final client = PusherClient(pusherKey, testOptions(), autoConnect: false);
      addTearDown(client.dispose);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(client.connectionState, 'DISCONNECTED');
      await client.connect();
      await waitUntil(() => client.connectionState == 'CONNECTED',
          'CONNECTED after connect()');
    });
  });

  group('public channels', () {
    testWidgets('subscribe, receive, bind replace, unbind, bindGlobal',
        (tester) async {
      final t = TestClient(testOptions());
      final name = 'test-public-${unique()}';
      final channel = t.client.subscribe(name);
      expect(t.client.subscribe(name), same(channel));
      final first = <PusherEvent>[];
      final second = <PusherEvent>[];
      await channel.bind('my-event', first.add);
      await channel.bind('my-event', second.add); // replaces the first
      final recorder = await subscribeAndWait(channel);
      expect(recorder.named('pusher:subscription_succeeded').single.data, '{}');

      await restTrigger(name, 'my-event', '{"hello":"world"}');
      await waitUntil(() => second.isNotEmpty, 'bound callback to fire');
      expect(second.single.eventName, 'my-event');
      expect(second.single.channelName, name);
      expect(second.single.data, '{"hello":"world"}');
      expect(first, isEmpty, reason: 'bind replaces the previous callback');
      final global = await recorder.waitFor('my-event');
      expect(global.data, '{"hello":"world"}');

      await channel.unbind('my-event');
      await restTrigger(name, 'my-event', 'plain text');
      final again = await recorder.waitFor('my-event', skip: 1);
      expect(again.data, 'plain text');
      expect(second, hasLength(1), reason: 'unbind stops delivery');

      await t.client.unsubscribe(name);
      expect(t.client.channel(name), isNull);
      expect(channel.isSubscribed, isFalse);
      await restTrigger(name, 'my-event', 'after unsubscribe');
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(recorder.named('my-event'), hasLength(2));
    });

    testWidgets('object data from server arrives as JSON string',
        (tester) async {
      final t = TestClient(testOptions());
      final name = 'test-object-data-${unique()}';
      final channel = t.client.subscribe(name);
      final recorder = await subscribeAndWait(channel);

      // Some servers (laravel-websockets, soketi) forward `data` as a JSON
      // value instead of a JSON-encoded string.
      const object = {
        'a': 1,
        'b': {'c': 'x'},
        'd': [1, 2],
      };
      await restTrigger(name, 'object-event', object, rawJsonData: true);
      final event = await recorder.waitFor('object-event');
      expect(event.data, isA<String>());
      expect(jsonDecode(event.data!), object);

      await restTrigger(name, 'array-event', [1, 'two'], rawJsonData: true);
      final array = await recorder.waitFor('array-event');
      expect(jsonDecode(array.data!), [1, 'two']);

      await restTrigger(name, 'number-event', 42, rawJsonData: true);
      final number = await recorder.waitFor('number-event');
      expect(jsonDecode(number.data!), 42);
    });

    testWidgets('subscribe before the connection is up', (tester) async {
      final client = PusherClient(pusherKey, testOptions(), autoConnect: false);
      addTearDown(client.dispose);
      final name = 'test-early-${unique()}';
      final channel = client.subscribe(name);
      final recorder = Recorder(channel);
      await client.connect();
      await recorder.waitFor('pusher:subscription_succeeded');
    });
  });

  group('private channels', () {
    testWidgets('authorizer callback', (tester) async {
      final calls = <List<String>>[];
      final t = TestClient(testOptions(authorizer: (channel, socketId) async {
        calls.add([channel, socketId]);
        return authData(socketId, channel);
      }));
      final name = 'private-auth-cb-${unique()}';
      final channel = t.client.subscribe(name);
      final recorder = await subscribeAndWait(channel);
      expect(calls, hasLength(1));
      expect(calls.single.first, name);
      expect(calls.single.last, t.client.socketId);

      await restTrigger(name, 'secret-event', {'n': 1});
      final event = await recorder.waitFor('secret-event');
      expect(jsonDecode(event.data!), {'n': 1});
    });

    testWidgets('PusherAuth form body, headers and params', (tester) async {
      final server = await AuthServer.start();
      server.requiredAuthorization = 'Bearer form-token';
      final t = TestClient(testOptions(
        auth: PusherAuth(
          server.url,
          headers: {'Authorization': 'Bearer form-token', 'X-Custom': 'abc'},
          params: {'foo': 'bar'},
        ),
      ));
      final name = 'private-auth-form-${unique()}';
      final recorder = await subscribeAndWait(t.client.subscribe(name));
      expect(server.requests, hasLength(1),
          reason: 'one authorization per subscription: '
              '${server.requests.map((r) => r.fields).toList()}');
      final request = server.requests.single;
      expect(request.contentType, 'application/x-www-form-urlencoded');
      expect(request.fields['socket_id'], t.client.socketId);
      expect(request.fields['channel_name'], name);
      expect(request.fields['foo'], 'bar');
      expect(request.headers.value('x-custom'), 'abc');
      expect(request.headers.value('authorization'), 'Bearer form-token');

      await restTrigger(name, 'e', 'ok');
      expect((await recorder.waitFor('e')).data, 'ok');
    });

    testWidgets('PusherAuth JSON body, headers and params', (tester) async {
      final server = await AuthServer.start();
      final t = TestClient(testOptions(
        auth: PusherAuth(
          server.url,
          headers: {
            'Content-Type': 'application/json',
            'X-Custom': 'json-abc',
          },
          params: {'foo': 'bar-json'},
        ),
      ));
      final name = 'private-auth-json-${unique()}';
      await subscribeAndWait(t.client.subscribe(name));
      expect(server.requests, hasLength(1),
          reason: 'one authorization per subscription: '
              '${server.requests.map((r) => r.fields).toList()}');
      final request = server.requests.single;
      expect(request.contentType, 'application/json');
      expect(request.fields['socket_id'], t.client.socketId);
      expect(request.fields['channel_name'], name);
      expect(request.fields['foo'], 'bar-json');
      expect(request.headers.value('x-custom'), 'json-abc');
    });

    testWidgets('auth failure (403) then updateAuth and retry', (tester) async {
      final server = await AuthServer.start();
      server.requiredAuthorization = 'Bearer good';
      final t = TestClient(testOptions(
        auth: PusherAuth(server.url, headers: {'Authorization': 'Bearer bad'}),
      ));
      final name = 'private-auth-retry-${unique()}';
      final channel = t.client.subscribe(name);
      final recorder = Recorder(channel);
      final error = await recorder.waitFor('pusher:subscription_error');
      final data = jsonDecode(error.data!) as Map<String, dynamic>;
      expect(data['status'], 403, reason: 'data: ${error.data}');
      expect(data['type'], 'AuthError');
      expect(channel.isSubscribed, isFalse);

      t.client.updateAuth(
        PusherAuth(server.url, headers: {'Authorization': 'Bearer good'}),
      );
      expect(t.client.subscribe(name), same(channel));
      await recorder.waitFor('pusher:subscription_succeeded');
      expect(channel.isSubscribed, isTrue);
      expect(server.requests, hasLength(2));
    });

    testWidgets('no authorizer configured yields subscription_error',
        (tester) async {
      final t = TestClient(testOptions());
      final channel = t.client.subscribe('private-noauth-${unique()}');
      final recorder = Recorder(channel);
      final error = await recorder.waitFor('pusher:subscription_error');
      expect(error.data, contains('No authorizer configured'));
    });
  });

  group('presence channels', () {
    testWidgets('members, member_added, member_removed', (tester) async {
      final a = TestClient(
          testOptions(authorizer: userAuthorizer('user-a', {'name': 'Alice'})));
      final b = TestClient(testOptions(
          authorizer: userAuthorizer('user-b', {'name': 'Bob', 'n': 2})));
      final name = 'presence-room-${unique()}';

      final chA = a.client.subscribe(name) as PresenceChannel;
      final recA = await subscribeAndWait(chA);
      expect(chA.me, 'user-a');
      expect(chA.members, {
        'user-a': {'name': 'Alice'},
      });
      expect(chA.memberCount, 1);

      final chB = b.client.subscribe(name) as PresenceChannel;
      final recB = await subscribeAndWait(chB);
      final added = await recA.waitFor('pusher:member_added');
      expect(added.userId, 'user-b');
      expect(jsonDecode(added.data!), {
        'user_id': 'user-b',
        'user_info': {'name': 'Bob', 'n': 2},
      });
      expect(chA.memberCount, 2);
      expect(chA.members['user-b'], {'name': 'Bob', 'n': 2});
      expect(chB.me, 'user-b');
      expect(chB.memberCount, 2);
      expect(chB.members.keys, unorderedEquals(['user-a', 'user-b']));
      expect(chB.members['user-a'], {'name': 'Alice'});
      final presence =
          jsonDecode(recB.named('pusher:subscription_succeeded').single.data!)
              as Map<String, dynamic>;
      expect(presence['presence']['count'], 2);

      await b.client.unsubscribe(name);
      final removed = await recA.waitFor('pusher:member_removed');
      expect(removed.userId, 'user-b');
      expect(jsonDecode(removed.data!)['user_id'], 'user-b');
      await waitUntil(() => chA.memberCount == 1, 'A to see 1 member');
      expect(chA.members.keys, ['user-a']);
    });
  });

  group('client events', () {
    testWidgets('private channel: A to B, auto client- prefix', (tester) async {
      final a = TestClient(testOptions(authorizer: userAuthorizer('a')));
      final b = TestClient(testOptions(authorizer: userAuthorizer('b')));
      final name = 'private-chat-${unique()}';
      final chA = a.client.subscribe(name);
      final chB = b.client.subscribe(name);
      final recA = Recorder(chA);
      final recB = Recorder(chB);
      await subscribeAndWait(chA, recA);
      await subscribeAndWait(chB, recB);

      await chA.trigger('client-typing', {'user': 'a', 'typing': true});
      final event = await recB.waitFor('client-typing');
      expect(jsonDecode(event.data!), {'user': 'a', 'typing': true});

      await chA.trigger('stopped', 'raw string');
      final prefixed = await recB.waitFor('client-stopped');
      expect(prefixed.data, 'raw string');
    });

    testWidgets('presence channel: userId of the sender', (tester) async {
      final a = TestClient(testOptions(authorizer: userAuthorizer('user-a')));
      final b = TestClient(testOptions(authorizer: userAuthorizer('user-b')));
      final name = 'presence-chat-${unique()}';
      final chA = a.client.subscribe(name);
      final chB = b.client.subscribe(name);
      final recA = Recorder(chA);
      final recB = Recorder(chB);
      await subscribeAndWait(chA, recA);
      await subscribeAndWait(chB, recB);

      await chA.trigger('client-ping', {'n': 1});
      final event = await recB.waitFor('client-ping');
      expect(jsonDecode(event.data!), {'n': 1});
      if (platformReportsClientEventUserId) {
        expect(event.userId, 'user-a');
      }
    });

    testWidgets('trigger before subscribed or on a public channel throws',
        (tester) async {
      final t = TestClient(testOptions(authorizer: userAuthorizer('a')));
      final priv = t.client.subscribe('private-early-${unique()}');
      await expectLater(
          priv.trigger('client-x', 'y'), throwsA(isA<PusherException>()));
      final pub = t.client.subscribe('test-public-trigger-${unique()}');
      await subscribeAndWait(pub);
      await expectLater(
          pub.trigger('client-x', 'y'), throwsA(isA<PusherException>()));
    });
  });

  group('private-encrypted channels', () {
    testWidgets('REST-triggered encrypted event is decrypted', (tester) async {
      final key = randomBytes(32);
      final name = 'private-encrypted-${unique()}';
      final t = TestClient(testOptions(
        authorizer: (channel, socketId) async => authData(
          socketId,
          channel,
          sharedSecret: base64Encode(key),
        ),
      ));
      final channel = t.client.subscribe(name);
      final recorder = await subscribeAndWait(channel);

      const plaintext = '{"secret":"value","n":42}';
      final nonce = randomBytes(24);
      final boxed = SecretBox(key).encrypt(
        Uint8List.fromList(utf8.encode(plaintext)),
        nonce: nonce,
      );
      await restTrigger(name, 'secret-event', {
        'nonce': base64Encode(boxed.nonce),
        'ciphertext': base64Encode(boxed.cipherText),
      });
      final event = await recorder.waitFor('secret-event');
      expect(event.data, plaintext);
    });
  });

  group('lifecycle and isolation', () {
    testWidgets('dispose makes the client unusable; a new one works',
        (tester) async {
      final t = TestClient(testOptions());
      await t.waitConnected();
      await t.client.dispose();
      expect(() => t.client.subscribe('x'), throwsStateError);
      expect(() => t.client.connectionState, throwsStateError);
      expect(() => t.client.socketId, throwsStateError);
      await expectLater(t.client.connect(), throwsStateError);
      await expectLater(t.client.disconnect(), throwsStateError);
      await t.client.dispose(); // idempotent

      final t2 = TestClient(testOptions());
      await t2.waitConnected();
      final name = 'test-after-dispose-${unique()}';
      final rec = await subscribeAndWait(t2.client.subscribe(name));
      await restTrigger(name, 'e', 'still works');
      expect((await rec.waitFor('e')).data, 'still works');
    });

    testWidgets('events of one instance never reach another', (tester) async {
      final a = TestClient(testOptions());
      final b = TestClient(testOptions());
      final id = unique();
      final chA = a.client.subscribe('test-iso-a-$id');
      final chB = b.client.subscribe('test-iso-b-$id');
      final sharedA = a.client.subscribe('test-iso-shared-$id');
      final sharedB = b.client.subscribe('test-iso-shared-$id');
      final recA = Recorder(chA);
      final recB = Recorder(chB);
      final recSharedA = Recorder(sharedA);
      final recSharedB = Recorder(sharedB);
      await subscribeAndWait(chA, recA);
      await subscribeAndWait(chB, recB);
      await subscribeAndWait(sharedA, recSharedA);
      await subscribeAndWait(sharedB, recSharedB);

      await restTrigger('test-iso-a-$id', 'e', 'for-a');
      await restTrigger('test-iso-shared-$id', 'e', 'for-both');
      await recA.waitFor('e');
      await recSharedA.waitFor('e');
      await recSharedB.waitFor('e');
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(recA.named('e'), hasLength(1));
      expect(recB.named('e'), isEmpty);
      expect(recSharedA.named('e'), hasLength(1), reason: 'no duplicates');
      expect(recSharedB.named('e'), hasLength(1), reason: 'no duplicates');
      expect(a.client.socketId, isNot(b.client.socketId));

      // Disconnecting A leaves B connected.
      await a.client.disconnect();
      await waitUntil(
          () => a.client.connectionState == 'DISCONNECTED', 'A disconnected');
      expect(b.client.connectionState, 'CONNECTED');
    });
  });
}
