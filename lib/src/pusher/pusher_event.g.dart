// YOU SHOULD MODIFY BY HAND

part of 'pusher_event.dart';

PusherEvent _$PusherEventFromJson(Map<String, dynamic> json) {
  return PusherEvent(
    channelName: json['channelName'] as String?,
    eventName: json['eventName'] as String?,
    data: json['data'] as String?,
    userId: json['userId'] as String?,
  );
}

Map<String, dynamic> _$PusherEventToJson(PusherEvent instance) =>
    <String, dynamic>{
      'channelName': instance.channelName,
      'eventName': instance.eventName,
      'data': instance.data,
      'userId': instance.userId,
    };
