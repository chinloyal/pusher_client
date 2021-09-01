// YOU SHOULD MODIFY BY HAND

part of 'connection_error.dart';

ConnectionError _$ConnectionErrorFromJson(Map<String, dynamic> json) {
  return ConnectionError(
    message: json['message'] as String?,
    code: json['code'] as String?,
    exception: json['exception'] as String?,
  );
}

Map<String, dynamic> _$ConnectionErrorToJson(ConnectionError instance) =>
    <String, dynamic>{
      'message': instance.message,
      'code': instance.code,
      'exception': instance.exception,
    };
