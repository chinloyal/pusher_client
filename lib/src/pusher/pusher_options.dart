import 'package:pusher_client/src/pusher/pusher_auth.dart';

part 'pusher_options.g.dart';

class PusherOptions {
  /// Sets the authorization options to be used when authenticating private,
  /// private-encrypted and presence channels.
  final PusherAuth? auth;

  /// A "cluster" represents the physical location of the servers that handle
  /// requests from your Channels app.
  ///
  /// For example, the Channels cluster `mt1`  is in Northern Virginia
  /// in the United States.
  final String? cluster;

  /// The host to which connections will be made.
  final String? host;

  /// Whether the connection to Pusher should be use TLS.
  final bool? encrypted;

  /// The number of milliseconds of inactivity at which a "ping" will be
  /// triggered to check the connection.
  final int? activityTimeout;

  /// The port to which non TLS connections will be made.
  final int? wsPort;

  /// The port to which encrypted connections will be made.
  final int? wssPort;

  /// The number of milliseconds after a "ping" is sent that the client will
  /// wait to receive a "pong" response from the server before considering the
  /// connection broken and triggering a transition to the disconnected state.
  ///
  /// The default value is 30,000.
  final int? pongTimeout;

  /// Number of reconnect attempts when websocket connection failed
  final int? maxReconnectionAttempts;

  /// The delay in two reconnection extends exponentially (1, 2, 4, .. seconds)
  /// This property sets the maximum in between two reconnection attempts.
  final int? maxReconnectGapInSeconds;

  PusherOptions({
    this.auth,
    this.cluster,
    this.host = "ws.pusherapp.com",
    this.wsPort = 80,
    this.wssPort = 443,
    this.encrypted = true,
    this.activityTimeout = 120000,
    this.pongTimeout = 30000,
    this.maxReconnectionAttempts = 6,
    this.maxReconnectGapInSeconds = 30,
  });

  factory PusherOptions.fromJson(Map<String, dynamic> json) =>
      _$PusherOptionsFromJson(json);
  Map<String, dynamic> toJson() => _$PusherOptionsToJson(this);
}
