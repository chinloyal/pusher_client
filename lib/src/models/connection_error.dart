import 'package:json_annotation/json_annotation.dart';

part 'connection_error.g.dart';

@JsonSerializable()
class ConnectionError {
  final String message;
  final String code;
  final String exception;

  ConnectionError({this.message, this.code, this.exception});

  factory ConnectionError.fromJson(Map<String, dynamic> json) =>
      _$ConnectionErrorFromJson(json);

  Map<String, dynamic> toJson() => _$ConnectionErrorToJson(this);
}
