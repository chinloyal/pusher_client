import 'package:flutter/material.dart';

import 'config.dart';
import 'home_page.dart';

void main() => runApp(PusherDemoApp(config: DemoConfig.fromEnvironment()));

/// Root widget of the demo. Pass a [config] to override the dart-defines.
class PusherDemoApp extends StatelessWidget {
  const PusherDemoApp({super.key, required this.config});

  final DemoConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pusher_client demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomePage(config: config),
    );
  }
}
