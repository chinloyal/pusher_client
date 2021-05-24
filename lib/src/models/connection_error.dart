part 'connection_error.g.dart';

class ConnectionError {
  /// A message indicating the cause of the error.
  final String? message;

  /// The error code for the message. Can be null.
  final String? code;

  /// The exception that was thrown, if any. Can be null.
  final String? exception;

  ConnectionError({this.message, this.code, this.exception});

  factory ConnectionError.fromJson(Map<String, dynamic> json) =>
      _$ConnectionErrorFromJson(json);

  Map<String, dynamic> toJson() => _$ConnectionErrorToJson(this);
}
