part 'pusher_auth.g.dart';

class PusherAuth {
  /// The endpoint to be called when authenticating.
  final String? endpoint;

  /// Additional headers to be sent as part of the request.
  final Map<String, String>? headers;

  PusherAuth(
    this.endpoint, {
    this.headers = const {'Content-Type': 'application/json'},
  });

  factory PusherAuth.fromJson(Map<String, dynamic> json) =>
      _$PusherAuthFromJson(json);
  Map<String, dynamic> toJson() => _$PusherAuthToJson(this);
}
