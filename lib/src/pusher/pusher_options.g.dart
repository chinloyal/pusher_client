// YOU SHOULD MODIFY BY HAND

part of 'pusher_options.dart';

PusherOptions _$PusherOptionsFromJson(Map<String, dynamic> json) {
  return PusherOptions(
    auth: json['auth'] == null
        ? null
        : PusherAuth.fromJson(json['auth'] as Map<String, dynamic>),
    cluster: json['cluster'] as String?,
    host: json['host'] as String?,
    wsPort: json['wsPort'] as int?,
    wssPort: json['wssPort'] as int?,
    encrypted: json['encrypted'] as bool?,
    activityTimeout: json['activityTimeout'] as int?,
    pongTimeout: json['pongTimeout'] as int?,
    maxReconnectionAttempts: json['maxReconnectionAttempts'] as int?,
    maxReconnectGapInSeconds: json['maxReconnectGapInSeconds'] as int?,
  );
}

Map<String, dynamic> _$PusherOptionsToJson(PusherOptions instance) =>
    <String, dynamic>{
      'auth': instance.auth,
      'cluster': instance.cluster,
      'host': instance.host,
      'encrypted': instance.encrypted,
      'activityTimeout': instance.activityTimeout,
      'pongTimeout': instance.pongTimeout,
      'wsPort': instance.wsPort,
      'wssPort': instance.wssPort,
      'maxReconnectionAttempts': instance.maxReconnectionAttempts,
      'maxReconnectGapInSeconds': instance.maxReconnectGapInSeconds,
    };
