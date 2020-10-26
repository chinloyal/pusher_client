import 'package:json_annotation/json_annotation.dart';

part 'pusher_event.g.dart';

@JsonSerializable()
class PusherEvent {
  final String channelName;
  final String eventName;
  final String data;
  final String userId;

  PusherEvent({
    this.channelName,
    this.eventName,
    this.data,
    this.userId,
  });

  factory PusherEvent.fromJson(Map<String, dynamic> json) =>
      _$PusherEventFromJson(json);
  Map<String, dynamic> toJson() => _$PusherEventToJson(this);
}
