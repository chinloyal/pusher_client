import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_client_example/config.dart';
import 'package:pusher_client_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.github.chinloyal/pusher_client');
  const eventChannel =
      EventChannel('com.github.chinloyal/pusher_client_stream');
  final binding = TestDefaultBinaryMessengerBinding.instance;

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => null,
    );
    binding.defaultBinaryMessenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.defaultBinaryMessenger.setMockStreamHandler(eventChannel, null);
  });

  testWidgets('renders the main controls', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const PusherDemoApp(
        config: DemoConfig(key: 'k', host: 'localhost', port: 6001, tls: false),
      ),
    );
    await tester.pump();

    expect(find.text('pusher_client demo'), findsOneWidget);
    expect(find.text('ws://localhost:6001'), findsOneWidget);
    expect(find.text('DISCONNECTED'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Subscribe'), findsOneWidget);
    expect(find.text('No subscribed channels.'), findsOneWidget);
    expect(find.text('No events yet.'), findsOneWidget);
    expect(find.text('Trigger'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('channel-field')), 'my-channel');
    await tester.tap(find.byKey(const Key('subscribe')));
    await tester.pump();
    expect(find.text('my-channel'), findsOneWidget);
    expect(find.text('Unsubscribe'), findsOneWidget);
  });
}
