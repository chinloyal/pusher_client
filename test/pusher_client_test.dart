import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_client/pusher_client.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MethodChannel channel =
      const MethodChannel('com.github.chinloyal/pusher_client');
  group('PusherClient Test | ', () {
    setUp(() {
      channel.setMockMethodCallHandler((call) {
        switch (call.method) {
          case 'init':
            return null;
          case 'connect':
            return null;
          default:
            throw UnimplementedError();
        }
      });
    });

    test('Pusher client returns a singleton', () {
      var pusher1 = PusherClient('key', PusherOptions());
      var pusher2 = PusherClient('key', PusherOptions());

      expect(pusher1.hashCode, pusher2.hashCode);
    });

    // test()
  });
}
