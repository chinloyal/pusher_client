import 'package:pusher_client/src/models/connection_error.dart';
import 'package:pusher_client/src/models/connection_state_change.dart';
import 'package:pusher_client/src/pusher/pusher_event.dart';

part 'event_stream_result.g.dart';

class EventStreamResult {
  final ConnectionStateChange? connectionStateChange;
  final ConnectionError? connectionError;
  final PusherEvent? pusherEvent;

  EventStreamResult({
    this.connectionStateChange,
    this.connectionError,
    this.pusherEvent,
  });

  bool get isConnectionStateChange => connectionStateChange != null;
  bool get isConnectionError => connectionError != null;
  bool get isPusherEvent => pusherEvent != null;

  factory EventStreamResult.fromJson(Map<String, dynamic> json) =>
      _$EventStreamResultFromJson(json);
  Map<String, dynamic> toJson() => _$EventStreamResultToJson(this);
}
