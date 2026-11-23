// Shared helpers for the integration tests: configuration, signing, REST
// trigger, an in-app auth endpoint and event recording.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_client/pusher_client.dart';

const pusherHost =
    String.fromEnvironment('PUSHER_HOST', defaultValue: '127.0.0.1');
const pusherPort = int.fromEnvironment('PUSHER_PORT', defaultValue: 6001);
const pusherKey = String.fromEnvironment('PUSHER_KEY', defaultValue: 'app-key');
const pusherSecret =
    String.fromEnvironment('PUSHER_SECRET', defaultValue: 'app-secret');
const pusherAppId =
    String.fromEnvironment('PUSHER_APP_ID', defaultValue: 'app-id');

const waitTimeout = Duration(seconds: 15);

final _random = Random.secure();

/// A unique suffix so tests never share channels.
String unique() => _random.nextInt(1 << 32).toRadixString(36);

Uint8List randomBytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String hmacHex(String secret, String message) =>
    _hex(Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(message)).bytes);

/// Pusher channel authorization signature (`key:hmac`).
String signChannel(String socketId, String channel, [String? channelData]) {
  final toSign = channelData == null
      ? '$socketId:$channel'
      : '$socketId:$channel:$channelData';
  return '$pusherKey:${hmacHex(pusherSecret, toSign)}';
}

/// Auth data for [channel], as an `authorizer` callback would return it.
PusherAuthorizationData authData(
  String socketId,
  String channel, {
  String? userId,
  Object? userInfo,
  String? sharedSecret,
}) {
  String? channelData;
  if (userId != null) {
    channelData = jsonEncode({'user_id': userId, 'user_info': userInfo});
  }
  return PusherAuthorizationData(
    auth: signChannel(socketId, channel, channelData),
    channelData: channelData,
    sharedSecret: sharedSecret,
  );
}

/// Triggers [event] on [channels] via the signed Pusher REST API.
Future<void> restTrigger(
  String channel,
  String event,
  Object data,
) async {
  final body = jsonEncode({
    'name': event,
    'channels': [channel],
    'data': data is String ? data : jsonEncode(data),
  });
  final path = '/apps/$pusherAppId/events';
  final params = <String, String>{
    'auth_key': pusherKey,
    'auth_timestamp':
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
    'auth_version': '1.0',
    'body_md5': md5.convert(utf8.encode(body)).toString(),
  };
  final keys = params.keys.toList()..sort();
  final query = keys.map((k) => '$k=${params[k]}').join('&');
  final signature = hmacHex(pusherSecret, 'POST\n$path\n$query');
  final client = HttpClient();
  try {
    final request = await client
        .postUrl(Uri.parse(
            'http://$pusherHost:$pusherPort$path?$query&auth_signature=$signature'))
        .timeout(waitTimeout);
    final bytes = utf8.encode(body);
    request.headers.contentType = ContentType.json;
    // soketi (uWebSockets.js) does not read chunked request bodies.
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(waitTimeout);
    final text = await utf8.decodeStream(response);
    if (response.statusCode != 200) {
      fail('REST trigger of $event on $channel failed: '
          '${response.statusCode} $text');
    }
  } finally {
    client.close(force: true);
  }
}

/// Polls [condition] until true, failing with [what] after [timeout].
Future<void> waitUntil(
  bool Function() condition,
  String what, {
  Duration timeout = waitTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after ${timeout.inSeconds}s waiting for: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// Records every event of a channel (via `bindGlobal`).
class Recorder {
  Recorder(Channel channel) : name = channel.name {
    channel.bindGlobal(events.add);
  }

  final String name;
  final List<PusherEvent> events = [];

  List<PusherEvent> named(String eventName) =>
      events.where((e) => e.eventName == eventName).toList();

  /// Waits for an event called [eventName] (optionally matching [where]).
  Future<PusherEvent> waitFor(
    String eventName, {
    bool Function(PusherEvent e)? where,
    int skip = 0,
  }) async {
    PusherEvent? found;
    await waitUntil(() {
      final matches = events
          .where((e) => e.eventName == eventName && (where?.call(e) ?? true))
          .toList();
      if (matches.length > skip) found = matches[skip];
      return found != null;
    }, 'event "$eventName" on $name (got: ${events.map((e) => e.eventName).toList()})');
    return found!;
  }
}

/// A client plus the connection updates it reported.
class TestClient {
  TestClient(PusherOptions options, {String key = pusherKey}) {
    client = PusherClient(key, options, enableLogging: true);
    client.onConnectionStateChange(
        (s) => callbackStates.add(s.currentState ?? ''));
    streamSub = client.connectionStateChanges
        .listen((s) => streamStates.add(s.currentState ?? ''));
    client.onConnectionError(errors.add);
    addTearDown(dispose);
  }

  late final PusherClient client;
  late final StreamSubscription<ConnectionStateChange> streamSub;
  final callbackStates = <String>[];
  final streamStates = <String>[];
  final errors = <ConnectionError>[];

  Future<void> waitConnected() async {
    await waitUntil(
      () => callbackStates.contains('CONNECTED') && client.socketId != null,
      'CONNECTED (callback states: $callbackStates, stream: $streamStates, '
      'errors: $errors)',
    );
  }

  Future<void> dispose() async {
    await streamSub.cancel();
    await client.dispose();
  }
}

PusherOptions testOptions({
  PusherAuth? auth,
  PusherAuthorizer? authorizer,
}) =>
    PusherOptions(
      host: pusherHost,
      wsPort: pusherPort,
      wssPort: pusherPort,
      encrypted: false,
      auth: auth,
      authorizer: authorizer,
    );

/// Waits for `pusher:subscription_succeeded` on [channel].
Future<Recorder> subscribeAndWait(Channel channel, [Recorder? recorder]) async {
  final rec = recorder ?? Recorder(channel);
  await rec.waitFor('pusher:subscription_succeeded');
  await waitUntil(() => channel.isSubscribed, '${channel.name}.isSubscribed');
  return rec;
}

class AuthRequest {
  AuthRequest(this.contentType, this.headers, this.fields);

  final String contentType;
  final HttpHeaders headers;
  final Map<String, dynamic> fields;
}

/// A tiny channel-authorization endpoint running inside the test process.
class AuthServer {
  AuthServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<AuthServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = AuthServer._(server);
    addTearDown(s.close);
    return s;
  }

  final HttpServer _server;
  final List<AuthRequest> requests = [];

  /// When set, requests without exactly this `Authorization` header get 403.
  String? requiredAuthorization;

  /// When set, every request answers with this status.
  int? forceStatus;

  /// Shared secret returned for `private-encrypted-` channels.
  String? sharedSecret;

  String get url => 'http://127.0.0.1:${_server.port}/pusher/auth';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final contentType = request.headers.contentType?.mimeType ?? '';
    Map<String, dynamic> fields;
    try {
      fields = contentType == 'application/json'
          ? (jsonDecode(body) as Map).cast<String, dynamic>()
          : Uri.splitQueryString(body).cast<String, dynamic>();
    } catch (_) {
      fields = {};
    }
    requests.add(AuthRequest(contentType, request.headers, fields));

    Future<void> reply(int status, Object json) async {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(json));
      await request.response.close();
    }

    if (forceStatus != null) {
      return reply(forceStatus!, {'error': 'forced ${forceStatus!}'});
    }
    final required = requiredAuthorization;
    if (required != null &&
        request.headers.value('authorization') != required) {
      return reply(403, {'error': 'bad authorization header'});
    }
    final socketId = fields['socket_id']?.toString();
    final channel = fields['channel_name']?.toString();
    if (socketId == null || channel == null) {
      return reply(400, {'error': 'missing socket_id/channel_name'});
    }
    final userId = channel.startsWith('presence-')
        ? (fields['user_id']?.toString() ?? 'user-1')
        : null;
    final data = authData(
      socketId,
      channel,
      userId: userId,
      userInfo: userId == null ? null : {'name': 'User $userId'},
      sharedSecret:
          channel.startsWith('private-encrypted-') ? sharedSecret : null,
    );
    await reply(200, {
      'auth': data.auth,
      if (data.channelData != null) 'channel_data': data.channelData,
      if (data.sharedSecret != null) 'shared_secret': data.sharedSecret,
    });
  }
}
