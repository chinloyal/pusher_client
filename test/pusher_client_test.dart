import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_client/pusher_client.dart';

void main() {
  const MethodChannel channel = MethodChannel('pusher_client');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    // expect(await PusherClient.platformVersion, '42');
  });
}
