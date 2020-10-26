import 'package:json_annotation/json_annotation.dart';

part 'connection_state_change.g.dart';

@JsonSerializable()
class ConnectionStateChange {
  final String currentState;
  final String previousState;

  ConnectionStateChange({
    this.currentState,
    this.previousState,
  });

  factory ConnectionStateChange.fromJson(Map<String, dynamic> json) =>
      _$ConnectionStateChangeFromJson(json);
  Map<String, dynamic> toJson() => _$ConnectionStateChangeToJson(this);
}
