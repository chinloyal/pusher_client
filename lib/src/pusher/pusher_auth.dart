import 'package:json_annotation/json_annotation.dart';

part 'pusher_auth.g.dart';

@JsonSerializable()
class PusherAuth {
  final String endpoint;
  final Map<String, String> headers;

  PusherAuth(
    this.endpoint, {
    this.headers = const {'Content-Type': 'application/json'},
  });

  factory PusherAuth.fromJson(Map<String, dynamic> json) =>
      _$PusherAuthFromJson(json);
  Map<String, dynamic> toJson() => _$PusherAuthToJson(this);
}
