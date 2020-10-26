import 'package:pusher_client/src/pusher/pusher_auth.dart';
import 'package:json_annotation/json_annotation.dart';

part 'pusher_options.g.dart';

@JsonSerializable()
class PusherOptions {
  final PusherAuth auth;
  final String cluster;
  final String host;
  final bool encrypted;
  final int activityTimeout;
  final int pongTimeout;
  final int wsPort;
  final int wssPort;
  final int maxReconnectionAttempts;
  final int maxReconnectGapInSeconds;

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
