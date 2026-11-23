import 'package:pusher_client/pusher_client.dart';

/// Demo configuration, read from `--dart-define` values (see README.md).
class DemoConfig {
  const DemoConfig({
    this.key = '',
    this.cluster = 'mt1',
    this.host = '',
    this.port,
    this.tls = true,
    this.authEndpoint = '',
  });

  /// Reads `PUSHER_KEY`, `PUSHER_CLUSTER`, `PUSHER_HOST`, `PUSHER_PORT`,
  /// `PUSHER_TLS` and `AUTH_ENDPOINT` from the compile-time environment.
  factory DemoConfig.fromEnvironment() {
    const port = String.fromEnvironment('PUSHER_PORT');
    return DemoConfig(
      key: const String.fromEnvironment('PUSHER_KEY'),
      cluster:
          const String.fromEnvironment('PUSHER_CLUSTER', defaultValue: 'mt1'),
      host: const String.fromEnvironment('PUSHER_HOST'),
      port: int.tryParse(port),
      tls: const bool.fromEnvironment('PUSHER_TLS', defaultValue: true),
      authEndpoint: const String.fromEnvironment('AUTH_ENDPOINT'),
    );
  }

  final String key;
  final String cluster;
  final String host;
  final int? port;
  final bool tls;
  final String authEndpoint;

  bool get hasHost => host.isNotEmpty;

  /// The port used for the chosen scheme: `PUSHER_PORT`, else 443 (TLS) / 80.
  int get effectivePort => port ?? (tls ? 443 : 80);

  PusherOptions toOptions() => PusherOptions(
        auth: authEndpoint.isEmpty ? null : PusherAuth(authEndpoint),
        host: hasHost ? host : null,
        cluster: hasHost ? null : cluster,
        wsPort: effectivePort,
        wssPort: effectivePort,
        encrypted: tls,
      );

  /// One-line description of the target, shown in the app bar.
  String get summary => hasHost
      ? '${tls ? 'wss' : 'ws'}://$host:$effectivePort'
      : 'Pusher cluster $cluster';
}
