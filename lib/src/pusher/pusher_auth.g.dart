// YOU SHOULD MODIFY BY HAND

part of 'pusher_auth.dart';

PusherAuth _$PusherAuthFromJson(Map<String, dynamic> json) {
  return PusherAuth(
    json['endpoint'] as String?,
    headers: (json['headers'] as Map<String, dynamic>?)?.map(
      (k, e) => MapEntry(k, e as String),
    ),
  );
}

Map<String, dynamic> _$PusherAuthToJson(PusherAuth instance) =>
    <String, dynamic>{
      'endpoint': instance.endpoint,
      'headers': instance.headers,
    };
