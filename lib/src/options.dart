import 'package:meta/meta.dart';

import 'auth.dart';

/// Configuration of a `PusherClient`.
class PusherOptions {
  /// Creates the options for a client.
  const PusherOptions({
    this.auth,
    this.authorizer,
    this.cluster,
    this.host,
    this.wsPort = 80,
    this.wssPort = 443,
    this.encrypted = true,
    this.activityTimeout = 120000,
    this.pongTimeout = 30000,
    this.maxReconnectionAttempts = 6,
    this.maxReconnectGapInSeconds = 30,
  });

  /// Sets the authorization options used to authenticate private,
  /// private-encrypted and presence channels through an HTTP endpoint.
  ///
  /// Ignored when [authorizer] is set.
  final PusherAuth? auth;

  /// A custom authorizer. Takes precedence over [auth].
  final PusherAuthorizer? authorizer;

  /// A "cluster" represents the physical location of the servers that handle
  /// requests from your Channels app.
  ///
  /// For example, the Channels cluster `mt1` is in Northern Virginia in the
  /// United States. Ignored when [host] is set.
  final String? cluster;

  /// The host to which connections will be made, for self-hosted servers.
  ///
  /// Must be a bare hostname: no scheme, port or path. When set it wins over
  /// [cluster].
  final String? host;

  /// The port to which non TLS connections will be made.
  final int wsPort;

  /// The port to which TLS connections will be made.
  final int wssPort;

  /// Whether the connection to Pusher should use TLS.
  final bool encrypted;

  /// The number of milliseconds of inactivity at which a "ping" will be
  /// triggered to check the connection.
  final int activityTimeout;

  /// The number of milliseconds after a "ping" is sent that the client will
  /// wait to receive a "pong" response from the server before considering the
  /// connection broken and triggering a transition to the disconnected state.
  final int pongTimeout;

  /// Number of reconnect attempts when the websocket connection failed.
  final int maxReconnectionAttempts;

  /// The delay between two reconnection attempts extends exponentially
  /// (1, 2, 4, .. seconds). This sets the maximum gap between two attempts.
  final int maxReconnectGapInSeconds;

  /// The `options` map sent with the platform `init` call.
  @internal
  Map<String, Object?> toMap() => <String, Object?>{
        'cluster': cluster,
        'host': host,
        'wsPort': wsPort,
        'wssPort': wssPort,
        'useTLS': encrypted,
        'activityTimeout': activityTimeout,
        'pongTimeout': pongTimeout,
        'maxReconnectionAttempts': maxReconnectionAttempts,
        'maxReconnectGapInSeconds': maxReconnectGapInSeconds,
        'hasAuthorizer': auth != null || authorizer != null,
      };
}
