import 'package:flutter/services.dart';

import 'pusher_platform.dart';

/// [PusherPlatform] backed by a [MethodChannel] and an [EventChannel].
class MethodChannelPusherPlatform extends PusherPlatform {
  /// Creates the platform. The channels can be replaced for tests.
  MethodChannelPusherPlatform({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ??
            const MethodChannel('com.github.chinloyal/pusher_client'),
        _eventChannel = eventChannel ??
            const EventChannel('com.github.chinloyal/pusher_client_stream');

  final MethodChannel _method;
  final EventChannel _eventChannel;
  AuthorizeHandler? _authorizeHandler;
  Stream<Map<String, Object?>>? _events;

  @override
  Stream<Map<String, Object?>> get events => _events ??= _eventChannel
          .receiveBroadcastStream()
          .expand<Map<String, Object?>>((event) {
        final map = _convert(event);
        return map is Map<String, Object?> ? [map] : const [];
      });

  @override
  set authorizeHandler(AuthorizeHandler? handler) {
    _authorizeHandler = handler;
    _method.setMethodCallHandler(handler == null ? null : _handleCall);
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method != 'authorize') {
      throw MissingPluginException('Unknown method ${call.method}');
    }
    final handler = _authorizeHandler;
    final args = _convert(call.arguments);
    if (handler == null || args is! Map<String, Object?>) {
      throw PlatformException(
        code: 'AUTH_ERROR',
        message: handler == null
            ? 'No authorize handler registered'
            : 'Invalid authorize arguments',
        details: <String, Object?>{'status': null},
      );
    }
    final instanceId = args['instanceId'];
    final channelName = args['channelName'];
    final socketId = args['socketId'];
    if (instanceId is! String ||
        channelName is! String ||
        socketId is! String) {
      throw PlatformException(
        code: 'AUTH_ERROR',
        message: 'Invalid authorize arguments',
        details: <String, Object?>{'status': null},
      );
    }
    try {
      return await handler(instanceId, channelName, socketId);
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(
        code: 'AUTH_ERROR',
        message: e.toString(),
        details: <String, Object?>{'status': null},
      );
    }
  }

  /// Recursively converts `Map<Object?, Object?>` to `Map<String, Object?>`.
  static Object? _convert(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final e in value.entries) e.key.toString(): _convert(e.value),
      };
    }
    if (value is List) return value.map(_convert).toList();
    return value;
  }

  @override
  Future<void> disposeAll() =>
      _method.invokeMethod<void>('disposeAll', <String, Object?>{});

  @override
  Future<void> init(
    String instanceId,
    String appKey,
    Map<String, Object?> options,
    bool enableLogging,
  ) =>
      _method.invokeMethod<void>('init', <String, Object?>{
        'instanceId': instanceId,
        'appKey': appKey,
        'enableLogging': enableLogging,
        'options': options,
      });

  @override
  Future<void> connect(String instanceId) => _method.invokeMethod<void>(
        'connect',
        <String, Object?>{'instanceId': instanceId},
      );

  @override
  Future<void> disconnect(String instanceId) => _method.invokeMethod<void>(
        'disconnect',
        <String, Object?>{'instanceId': instanceId},
      );

  @override
  Future<void> dispose(String instanceId) => _method.invokeMethod<void>(
        'dispose',
        <String, Object?>{'instanceId': instanceId},
      );

  @override
  Future<void> subscribe(String instanceId, String channelName) =>
      _method.invokeMethod<void>('subscribe', <String, Object?>{
        'instanceId': instanceId,
        'channelName': channelName,
      });

  @override
  Future<void> unsubscribe(String instanceId, String channelName) =>
      _method.invokeMethod<void>('unsubscribe', <String, Object?>{
        'instanceId': instanceId,
        'channelName': channelName,
      });

  @override
  Future<void> trigger(
    String instanceId,
    String channelName,
    String eventName,
    String data,
  ) =>
      _method.invokeMethod<void>('trigger', <String, Object?>{
        'instanceId': instanceId,
        'channelName': channelName,
        'eventName': eventName,
        'data': data,
      });

  @override
  Future<String?> getSocketId(String instanceId) =>
      _method.invokeMethod<String>('getSocketId', <String, Object?>{
        'instanceId': instanceId,
      });
}
