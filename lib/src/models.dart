import 'dart:convert';

String? _asString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

/// An event received on a channel.
class PusherEvent {
  /// Creates a [PusherEvent].
  const PusherEvent({this.channelName, this.eventName, this.data, this.userId});

  /// Builds a [PusherEvent] from a platform event map.
  ///
  /// Non-string `data` is JSON encoded so [data] is always a string, exactly
  /// as Pusher delivers it.
  factory PusherEvent.fromMap(Map<String, Object?> map) {
    final rawData = map['data'];
    return PusherEvent(
      channelName: _asString(map['channelName']),
      eventName: _asString(map['eventName']),
      data: rawData == null
          ? null
          : (rawData is String ? rawData : jsonEncode(rawData)),
      userId: _asString(map['userId']),
    );
  }

  /// The name of the channel the event was received on.
  final String? channelName;

  /// The name of the event.
  final String? eventName;

  /// The event payload as delivered by Pusher (usually a JSON string).
  final String? data;

  /// The id of the user that triggered the event, or the member id for
  /// presence member events.
  final String? userId;

  @override
  bool operator ==(Object other) =>
      other is PusherEvent &&
      other.channelName == channelName &&
      other.eventName == eventName &&
      other.data == data &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(channelName, eventName, data, userId);

  @override
  String toString() =>
      'PusherEvent(channelName: $channelName, eventName: $eventName, '
      'data: $data, userId: $userId)';
}

/// Describes a change of the connection state.
class ConnectionStateChange {
  /// Creates a [ConnectionStateChange].
  const ConnectionStateChange({this.currentState, this.previousState});

  /// Builds a [ConnectionStateChange] from a platform event map.
  factory ConnectionStateChange.fromMap(Map<String, Object?> map) =>
      ConnectionStateChange(
        currentState: _asString(map['currentState']),
        previousState: _asString(map['previousState']),
      );

  /// The new state: `CONNECTING`, `CONNECTED`, `DISCONNECTING`,
  /// `DISCONNECTED` or `RECONNECTING`.
  final String? currentState;

  /// The state before the change.
  final String? previousState;

  @override
  bool operator ==(Object other) =>
      other is ConnectionStateChange &&
      other.currentState == currentState &&
      other.previousState == previousState;

  @override
  int get hashCode => Object.hash(currentState, previousState);

  @override
  String toString() => 'ConnectionStateChange(currentState: $currentState, '
      'previousState: $previousState)';
}

/// An error reported by Pusher or by the client library.
class ConnectionError {
  /// Creates a [ConnectionError].
  const ConnectionError({this.message, this.code, this.exception});

  /// Builds a [ConnectionError] from a platform event map.
  factory ConnectionError.fromMap(Map<String, Object?> map) => ConnectionError(
        message: _asString(map['message']),
        code: _asString(map['code']),
        exception: _asString(map['exception']),
      );

  /// A human readable description of the error.
  final String? message;

  /// The error code, for example `"4001"`, if there is one.
  final String? code;

  /// The underlying exception, if any, as a string.
  final String? exception;

  @override
  bool operator ==(Object other) =>
      other is ConnectionError &&
      other.message == message &&
      other.code == code &&
      other.exception == exception;

  @override
  int get hashCode => Object.hash(message, code, exception);

  @override
  String toString() =>
      'ConnectionError(message: $message, code: $code, exception: $exception)';
}

/// Thrown when an operation of this package fails, for example when
/// triggering a client event is not allowed.
class PusherException implements Exception {
  /// Creates a [PusherException].
  const PusherException(this.message, {this.code});

  /// A human readable description of the failure.
  final String message;

  /// A stable error code such as `TRIGGER_ERROR`, if there is one.
  final String? code;

  @override
  bool operator ==(Object other) =>
      other is PusherException &&
      other.message == message &&
      other.code == code;

  @override
  int get hashCode => Object.hash(message, code);

  @override
  String toString() =>
      'PusherException(${code == null ? '' : '$code: '}$message)';
}
