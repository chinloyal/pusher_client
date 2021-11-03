part 'pusher_auth.g.dart';

class PusherAuth {
  /// The endpoint to be called when authenticating.
  final String? endpoint;

  /// Additional headers to be sent as part of the request.
  final Map<String, String>? headers;

  /// Additional parameters to be sent as part of body of request
  /// If headers contain:
  /// ```
  ///        headers: {
  ///                 'Content-Type': 'application/x-www-form-urlencoded',
  ///               },
  ///```
  ///Then the params are sent to the [endpoint] in the body of the request
  final Map<String, String>? params;

  PusherAuth(
    this.endpoint, {
    this.params,
    this.headers = const {'Content-Type': 'application/json'},
  });

  factory PusherAuth.fromJson(Map<String, dynamic> json) => _$PusherAuthFromJson(json);

  Map<String, dynamic> toJson() => _$PusherAuthToJson(this);
}
