import 'dart:convert';

/// Pure conversion helpers for the web implementation. This file must not
/// import `dart:js_interop` so that it can be unit tested on the Dart VM.

/// Maps a pusher-js connection state to the §4.3 protocol state.
///
/// pusher-js states: `initialized`, `connecting`, `connected`, `unavailable`,
/// `failed`, `disconnected`.
String mapConnectionState(String? jsState) {
  switch (jsState) {
    case 'connecting':
      return 'CONNECTING';
    case 'connected':
      return 'CONNECTED';
    case 'unavailable':
      return 'RECONNECTING';
    case 'initialized':
    case 'disconnected':
    case 'failed':
    default:
      return 'DISCONNECTED';
  }
}

/// Builds the §5.1 `connectionStateChange` event, or `null` when the mapped
/// states are identical (e.g. `initialized` -> `disconnected`).
Map<String, Object?>? buildConnectionStateEvent(
  String instanceId,
  String? previous,
  String? current,
  String? socketId,
) {
  final prev = mapConnectionState(previous);
  final cur = mapConnectionState(current);
  if (prev == cur) return null;
  return <String, Object?>{
    'instanceId': instanceId,
    'type': 'connectionStateChange',
    'currentState': cur,
    'previousState': prev,
    'socketId': cur == 'CONNECTED' ? socketId : null,
  };
}

/// Builds the §5.2 `connectionError` event.
Map<String, Object?> buildConnectionErrorEvent(
  String instanceId, {
  String? message,
  Object? code,
  String? exception,
}) =>
    <String, Object?>{
      'instanceId': instanceId,
      'type': 'connectionError',
      'message': message,
      'code': code?.toString(),
      'exception': exception,
    };

/// Builds the pusher-js constructor options from the §4.1 options map.
///
/// `channelAuthorization` is added by the JS-facing code since it needs a
/// callback. `maxReconnectionAttempts` and `maxReconnectGapInSeconds` have no
/// pusher-js equivalent (it retries forever with its own back-off) and are
/// intentionally ignored.
Map<String, Object?> buildPusherJsOptions(Map<String, Object?> options) {
  final host = _nonEmpty(options['host']);
  final cluster = _nonEmpty(options['cluster']);
  final useTls = options['useTLS'] != false;
  final result = <String, Object?>{
    // pusher-js requires a cluster value even when a host is given.
    'cluster': cluster ?? 'mt1',
    'forceTLS': useTls,
    'enabledTransports': <String>['ws', 'wss'],
    'enableStats': false,
  };
  if (host != null) {
    result['wsHost'] = host;
    result['httpHost'] = host;
  }
  final wsPort = options['wsPort'];
  final wssPort = options['wssPort'];
  if (wsPort is int) result['wsPort'] = wsPort;
  if (wssPort is int) result['wssPort'] = wssPort;
  final activity = options['activityTimeout'];
  final pong = options['pongTimeout'];
  if (activity is int) result['activityTimeout'] = activity;
  if (pong is int) result['pongTimeout'] = pong;
  return result;
}

String? _nonEmpty(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// Builds the successful authorization result handed to pusher-js, omitting
/// null / non-string values.
Map<String, Object?> buildAuthResult(Map<String, Object?> authorization) {
  final result = <String, Object?>{};
  for (final key in const ['auth', 'channel_data', 'shared_secret']) {
    final value = authorization[key];
    if (value != null) result[key] = value;
  }
  return result;
}

/// Extracts the HTTP status from AUTH_ERROR `details`, if any.
int? authStatusFromDetails(Object? details) {
  if (details is Map) {
    final status = details['status'];
    if (status is int) return status;
    if (status is num) return status.toInt();
  }
  return null;
}

/// Normalises pusher-js' `pusher:subscription_error` payload to the §5.3
/// shape `{"type":"AuthError","error":msg,"status":int|null}`.
///
/// [data] is whatever pusher-js passed (usually a map with `type`, `error`
/// and optionally `status`, but possibly a string). [fallbackStatus] is the
/// status remembered from our own authorizer failure (pusher-js only reports
/// `status` for its built-in HTTP authorizer).
String normalizeSubscriptionError(Object? data, {int? fallbackStatus}) {
  String type = 'AuthError';
  String error = 'Subscription failed';
  int? status = fallbackStatus;
  if (data is String) {
    error = data;
  } else if (data is Map) {
    final t = data['type'];
    if (t is String && t.isNotEmpty) type = t;
    final e = data['error'] ?? data['message'];
    if (e != null) error = e.toString();
    final s = data['status'];
    if (s is num) {
      status = s.toInt();
    } else if (s is String) {
      status = int.tryParse(s) ?? status;
    }
  } else if (data != null) {
    error = data.toString();
  }
  return jsonEncode(<String, Object?>{
    'type': type,
    'error': error,
    'status': status,
  });
}

/// Builds the §5.3 presence `pusher:subscription_succeeded` data from the
/// member [hash] (`id -> info`) and [count].
String presenceSubscriptionData(Map<String, Object?> hash, {int? count}) =>
    jsonEncode(<String, Object?>{
      'presence': <String, Object?>{
        'count': count ?? hash.length,
        'ids': hash.keys.toList(),
        'hash': hash,
      },
    });

/// Data for `pusher:member_added`.
String memberAddedData(String id, Object? info) =>
    jsonEncode(<String, Object?>{'user_id': id, 'user_info': info});

/// Data for `pusher:member_removed`.
String memberRemovedData(String id) =>
    jsonEncode(<String, Object?>{'user_id': id});

/// Data for `pusher:subscription_count`.
String subscriptionCountData(int count) =>
    jsonEncode(<String, Object?>{'subscription_count': count});

/// Builds a §5.3 `event` map.
Map<String, Object?> buildChannelEvent(
  String instanceId,
  String channelName,
  String eventName,
  String? data, {
  String? userId,
}) =>
    <String, Object?>{
      'instanceId': instanceId,
      'type': 'event',
      'channelName': channelName,
      'eventName': eventName,
      'data': data,
      'userId': userId,
    };

/// Whether [eventName] is pusher-js internal and must not be forwarded.
bool isInternalEvent(String eventName) =>
    eventName.startsWith('pusher_internal:');

/// Whether the channel name denotes a presence channel.
bool isPresenceChannel(String channelName) =>
    channelName.startsWith('presence-');

/// Whether client events may be triggered on [channelName] (private or
/// presence, but not private-encrypted).
bool canTriggerOn(String channelName) =>
    channelName.startsWith('presence-') ||
    (channelName.startsWith('private-') &&
        !channelName.startsWith('private-encrypted-'));
