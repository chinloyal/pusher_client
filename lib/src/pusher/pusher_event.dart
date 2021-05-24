part 'pusher_event.g.dart';

class PusherEvent {
  /// The name of the channel that the event was triggered on. Not present
  /// in events without an associated channel, For example "pusher:error" events
  /// relating to the connection.
  final String? channelName;

  /// The name of the event.
  final String? eventName;

  /// The data that was passed when the event was triggered.
  final String? data;

  /// The ID of the user who triggered the event. Only present in
  /// client event on presence channels.
  final String? userId;

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
