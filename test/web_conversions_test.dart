import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_client/src/web/web_conversions.dart';

void main() {
  group('mapConnectionState', () {
    test('maps pusher-js states', () {
      expect(mapConnectionState('initialized'), 'DISCONNECTED');
      expect(mapConnectionState('disconnected'), 'DISCONNECTED');
      expect(mapConnectionState('connecting'), 'CONNECTING');
      expect(mapConnectionState('connected'), 'CONNECTED');
      expect(mapConnectionState('unavailable'), 'RECONNECTING');
      expect(mapConnectionState('failed'), 'DISCONNECTED');
      expect(mapConnectionState(null), 'DISCONNECTED');
      expect(mapConnectionState('weird'), 'DISCONNECTED');
    });
  });

  group('buildConnectionStateEvent', () {
    test('includes socketId only when connected', () {
      expect(
        buildConnectionStateEvent('i', 'connecting', 'connected', '1.2'),
        {
          'instanceId': 'i',
          'type': 'connectionStateChange',
          'currentState': 'CONNECTED',
          'previousState': 'CONNECTING',
          'socketId': '1.2',
        },
      );
      expect(
        buildConnectionStateEvent('i', 'connected', 'unavailable', '1.2')!,
        containsPair('socketId', null),
      );
    });

    test('suppresses no-op transitions', () {
      expect(
          buildConnectionStateEvent('i', 'initialized', 'disconnected', null),
          isNull);
      expect(buildConnectionStateEvent('i', 'failed', 'disconnected', null),
          isNull);
    });
  });

  test('buildConnectionErrorEvent stringifies the code', () {
    expect(
      buildConnectionErrorEvent('i', message: 'm', code: 4001, exception: 'e'),
      {
        'instanceId': 'i',
        'type': 'connectionError',
        'message': 'm',
        'code': '4001',
        'exception': 'e',
      },
    );
    expect(buildConnectionErrorEvent('i')['code'], isNull);
  });

  group('buildPusherJsOptions', () {
    Map<String, Object?> base([Map<String, Object?> o = const {}]) =>
        <String, Object?>{
          'cluster': null,
          'host': null,
          'wsPort': 80,
          'wssPort': 443,
          'useTLS': true,
          'activityTimeout': 120000,
          'pongTimeout': 30000,
          'maxReconnectionAttempts': 6,
          'maxReconnectGapInSeconds': 30,
          'hasAuthorizer': true,
          ...o,
        };

    test('cluster only', () {
      final r = buildPusherJsOptions(base({'cluster': 'eu'}));
      expect(r['cluster'], 'eu');
      expect(r.containsKey('wsHost'), isFalse);
      expect(r['forceTLS'], isTrue);
      expect(r['enabledTransports'], ['ws', 'wss']);
      expect(r['activityTimeout'], 120000);
      expect(r['pongTimeout'], 30000);
      expect(r['wsPort'], 80);
      expect(r['wssPort'], 443);
    });

    test('host only falls back to mt1 cluster', () {
      final r = buildPusherJsOptions(
        base({'host': 'ws.example.com', 'useTLS': false, 'wsPort': 6001}),
      );
      expect(r['wsHost'], 'ws.example.com');
      expect(r['httpHost'], 'ws.example.com');
      expect(r['cluster'], 'mt1');
      expect(r['forceTLS'], isFalse);
      expect(r['wsPort'], 6001);
    });

    test('host and cluster keep both', () {
      final r = buildPusherJsOptions(base({'host': 'h', 'cluster': 'ap1'}));
      expect(r['wsHost'], 'h');
      expect(r['cluster'], 'ap1');
    });

    test('neither host nor cluster defaults to mt1; ignores reconnection', () {
      final r = buildPusherJsOptions(base());
      expect(r['cluster'], 'mt1');
      expect(r.containsKey('maxReconnectionAttempts'), isFalse);
      expect(r.containsKey('maxReconnectGapInSeconds'), isFalse);
      expect(r.containsKey('hasAuthorizer'), isFalse);
    });
  });

  group('auth helpers', () {
    test('buildAuthResult omits nulls', () {
      expect(buildAuthResult({'auth': 'k:s', 'channel_data': null}),
          {'auth': 'k:s'});
      expect(
        buildAuthResult(
            {'auth': 'a', 'channel_data': 'c', 'shared_secret': 's', 'x': 1}),
        {'auth': 'a', 'channel_data': 'c', 'shared_secret': 's'},
      );
    });

    test('authStatusFromDetails', () {
      expect(authStatusFromDetails({'status': 403}), 403);
      expect(authStatusFromDetails({'status': 401.0}), 401);
      expect(authStatusFromDetails({'status': null}), isNull);
      expect(authStatusFromDetails('x'), isNull);
      expect(authStatusFromDetails(null), isNull);
    });
  });

  group('normalizeSubscriptionError', () {
    Map<String, Object?> parse(String s) =>
        jsonDecode(s) as Map<String, Object?>;

    test('map with status', () {
      expect(
        parse(normalizeSubscriptionError(
            {'type': 'AuthError', 'error': 'nope', 'status': 403})),
        {'type': 'AuthError', 'error': 'nope', 'status': 403},
      );
    });

    test('missing status uses fallback or null', () {
      expect(
        parse(normalizeSubscriptionError({'type': 'AuthError', 'error': 'x'},
            fallbackStatus: 401)),
        {'type': 'AuthError', 'error': 'x', 'status': 401},
      );
      expect(
        parse(normalizeSubscriptionError({'error': 'x'}))['status'],
        isNull,
      );
    });

    test('string and odd inputs', () {
      expect(parse(normalizeSubscriptionError('boom')),
          {'type': 'AuthError', 'error': 'boom', 'status': null});
      expect(parse(normalizeSubscriptionError(null))['error'], isNotEmpty);
      expect(
          parse(normalizeSubscriptionError({'status': '404'}))['status'], 404);
      expect(parse(normalizeSubscriptionError(42))['error'], '42');
    });
  });

  group('presence / member data', () {
    test('presenceSubscriptionData', () {
      final json = jsonDecode(presenceSubscriptionData(
        {
          '1': {'name': 'a'},
          '2': null,
        },
        count: 2,
      )) as Map<String, Object?>;
      expect(json, {
        'presence': {
          'count': 2,
          'ids': ['1', '2'],
          'hash': {
            '1': {'name': 'a'},
            '2': null,
          },
        },
      });
    });

    test('count defaults to hash length', () {
      final json = jsonDecode(presenceSubscriptionData({'x': 1}))
          as Map<String, Object?>;
      expect((json['presence']! as Map)['count'], 1);
    });

    test('member added / removed / count', () {
      expect(jsonDecode(memberAddedData('7', {'n': 1})), {
        'user_id': '7',
        'user_info': {'n': 1}
      });
      expect(jsonDecode(memberAddedData('7', null)),
          {'user_id': '7', 'user_info': null});
      expect(jsonDecode(memberRemovedData('7')), {'user_id': '7'});
      expect(jsonDecode(subscriptionCountData(3)), {'subscription_count': 3});
    });
  });

  group('channel helpers', () {
    test('buildChannelEvent', () {
      expect(
        buildChannelEvent('i', 'c', 'e', 'd', userId: 'u'),
        {
          'instanceId': 'i',
          'type': 'event',
          'channelName': 'c',
          'eventName': 'e',
          'data': 'd',
          'userId': 'u',
        },
      );
    });

    test('isInternalEvent', () {
      expect(isInternalEvent('pusher_internal:member_added'), isTrue);
      expect(isInternalEvent('pusher:member_added'), isFalse);
      expect(isInternalEvent('my-event'), isFalse);
    });

    test('canTriggerOn / isPresenceChannel', () {
      expect(canTriggerOn('private-a'), isTrue);
      expect(canTriggerOn('presence-a'), isTrue);
      expect(canTriggerOn('private-encrypted-a'), isFalse);
      expect(canTriggerOn('public'), isFalse);
      expect(isPresenceChannel('presence-a'), isTrue);
      expect(isPresenceChannel('private-a'), isFalse);
    });
  });
}
