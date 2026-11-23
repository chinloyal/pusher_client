import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_client/pusher_client.dart';

void main() {
  group('PusherEvent', () {
    test('fromMap reads all fields', () {
      final e = PusherEvent.fromMap({
        'channelName': 'c',
        'eventName': 'e',
        'data': '{"a":1}',
        'userId': 'u',
      });
      expect(e.channelName, 'c');
      expect(e.eventName, 'e');
      expect(e.data, '{"a":1}');
      expect(e.userId, 'u');
    });

    test('fromMap JSON-encodes non-string data and tolerates nulls', () {
      final e = PusherEvent.fromMap({
        'data': {'a': 1}
      });
      expect(e.data, '{"a":1}');
      expect(e.channelName, isNull);
      expect(PusherEvent.fromMap({'userId': 5}).userId, '5');
    });

    test('equality, hashCode and toString', () {
      const a = PusherEvent(channelName: 'c', eventName: 'e', data: 'd');
      const b = PusherEvent(channelName: 'c', eventName: 'e', data: 'd');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const PusherEvent(channelName: 'x')));
      expect(a.toString(), contains('eventName: e'));
    });
  });

  group('ConnectionStateChange', () {
    test('fromMap, equality, toString', () {
      final s = ConnectionStateChange.fromMap({
        'currentState': 'CONNECTED',
        'previousState': 'CONNECTING',
      });
      expect(s.currentState, 'CONNECTED');
      expect(s.previousState, 'CONNECTING');
      expect(
        s,
        const ConnectionStateChange(
          currentState: 'CONNECTED',
          previousState: 'CONNECTING',
        ),
      );
      expect(s.hashCode, isA<int>());
      expect(s, isNot(const ConnectionStateChange()));
      expect(s.toString(), contains('CONNECTED'));
    });
  });

  group('ConnectionError', () {
    test('fromMap, equality, toString', () {
      final e = ConnectionError.fromMap({
        'message': 'm',
        'code': 4001,
        'exception': 'x',
      });
      expect(e.message, 'm');
      expect(e.code, '4001');
      expect(e.exception, 'x');
      expect(
        e,
        const ConnectionError(message: 'm', code: '4001', exception: 'x'),
      );
      expect(e.hashCode, isA<int>());
      expect(e, isNot(const ConnectionError()));
      expect(e.toString(), contains('4001'));
    });
  });

  group('PusherException', () {
    test('equality and toString', () {
      const e = PusherException('boom', code: 'TRIGGER_ERROR');
      expect(e, const PusherException('boom', code: 'TRIGGER_ERROR'));
      expect(e.hashCode, isA<int>());
      expect(e, isNot(const PusherException('boom')));
      expect(e.toString(), contains('TRIGGER_ERROR'));
      expect(const PusherException('x').toString(), 'PusherException(x)');
    });
  });
}
