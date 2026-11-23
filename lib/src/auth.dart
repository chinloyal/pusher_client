import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Authorizes a subscription to a private, private-encrypted or presence
/// channel.
///
/// Called with the [channelName] and the connection's [socketId]; must return
/// the authorization data produced by your server. Throw to fail the
/// subscription (the channel then receives `pusher:subscription_error`).
typedef PusherAuthorizer = Future<PusherAuthorizationData> Function(
  String channelName,
  String socketId,
);

/// The built-in HTTP authorization options.
class PusherAuth {
  /// Creates the authorization options for [endpoint].
  const PusherAuth(
    this.endpoint, {
    this.headers = const {},
    this.params = const {},
  });

  /// The full URL to be called when authenticating.
  final String endpoint;

  /// Additional headers to be sent as part of the request.
  ///
  /// If a `content-type` header containing `application/json` is present the
  /// body is sent as JSON, otherwise as `application/x-www-form-urlencoded`.
  final Map<String, String> headers;

  /// Extra body parameters sent with `socket_id` and `channel_name`.
  final Map<String, String> params;
}

/// The result of authorizing a channel subscription.
class PusherAuthorizationData {
  /// Creates the authorization data.
  const PusherAuthorizationData({
    required this.auth,
    this.channelData,
    this.sharedSecret,
  });

  /// Builds the data from the JSON returned by an auth endpoint. Recognised
  /// keys: `auth`, `channel_data`, `shared_secret`.
  factory PusherAuthorizationData.fromJson(Map<String, dynamic> json) {
    final auth = json['auth'];
    if (auth is! String) {
      throw const FormatException('Authorization response has no "auth" key');
    }
    final channelData = json['channel_data'];
    final sharedSecret = json['shared_secret'];
    return PusherAuthorizationData(
      auth: auth,
      channelData: channelData == null
          ? null
          : (channelData is String ? channelData : jsonEncode(channelData)),
      sharedSecret: sharedSecret?.toString(),
    );
  }

  /// The auth signature, `<key>:<signature>`.
  final String auth;

  /// For presence channels: a JSON string `{"user_id":..,"user_info":..}`.
  final String? channelData;

  /// For private-encrypted channels: the base64 shared secret.
  final String? sharedSecret;

  /// The map returned to the native layer for an `authorize` call.
  Map<String, Object?> toMap() => <String, Object?>{
        'auth': auth,
        'channel_data': channelData,
        'shared_secret': sharedSecret,
      };
}

/// Builds the `AUTH_ERROR` exception reported to the native layer.
PlatformException authError(String message, {int? status}) => PlatformException(
      code: 'AUTH_ERROR',
      message: message,
      details: <String, Object?>{'status': status},
    );

/// Authorizes channels over HTTP using [PusherAuth].
class HttpAuthorizer {
  HttpAuthorizer._();

  /// Creates the HTTP client used for each authorization request.
  @visibleForTesting
  static http.Client Function() httpClientFactory = http.Client.new;

  /// Posts to [auth]'s endpoint and parses the response.
  ///
  /// Throws a [PlatformException] with code `AUTH_ERROR` on any failure.
  static Future<PusherAuthorizationData> authorize(
    PusherAuth auth,
    String channelName,
    String socketId,
  ) async {
    final fields = <String, String>{
      ...auth.params,
      'socket_id': socketId,
      'channel_name': channelName,
    };
    final headers = Map<String, String>.of(auth.headers);
    final contentTypeKey = headers.keys
        .where((k) => k.toLowerCase() == 'content-type')
        .firstOrNull;
    final contentType = contentTypeKey == null ? '' : headers[contentTypeKey]!;
    final String body;
    if (contentType.toLowerCase().contains('application/json')) {
      body = jsonEncode(fields);
    } else {
      body = fields.entries
          .map(
            (e) => '${Uri.encodeQueryComponent(e.key)}='
                '${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&');
      if (contentTypeKey == null) {
        headers['content-type'] = 'application/x-www-form-urlencoded';
      }
    }

    final client = httpClientFactory();
    try {
      final http.Response response;
      try {
        response = await client.post(
          Uri.parse(auth.endpoint),
          headers: headers,
          body: body,
        );
      } on Exception catch (e) {
        throw authError('Authorization request failed: $e');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var text = response.body;
        if (text.length > 500) text = text.substring(0, 500);
        throw authError(
          'Authorization request failed with status '
          '${response.statusCode}: $text',
          status: response.statusCode,
        );
      }
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const FormatException('Response is not a JSON object');
        }
        return PusherAuthorizationData.fromJson(
          decoded.cast<String, dynamic>(),
        );
      } on FormatException catch (e) {
        throw authError(
          'Invalid authorization response: ${e.message}',
          status: response.statusCode,
        );
      }
    } finally {
      client.close();
    }
  }
}
