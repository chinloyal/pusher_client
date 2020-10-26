import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pusher_client/pusher_client.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:pusher_client/src/models/connection_error.dart';
import 'package:pusher_client/src/models/connection_state_change.dart';
import 'package:pusher_client/src/models/event_stream_result.dart';
import 'package:pusher_client/src/pusher/channel.dart';

part 'pusher_client.g.dart';

class PusherClient {
  static const MethodChannel _channel =
      const MethodChannel('com.github.chinloyal/pusher_client');
  static const EventChannel _eventStream =
      const EventChannel('com.github.chinloyal/pusher_client_stream');

  static PusherClient _singleton;
  void Function(ConnectionStateChange) _onConnectionStateChange;
  void Function(ConnectionError) _onConnectionError;
  StreamSubscription _eventStreamSubscription;
  String _socketId;

  PusherClient._(
    String appKey,
    PusherOptions options, {
    bool enableLogging = true,
  });

  factory PusherClient(
    String appKey,
    PusherOptions options, {
    bool enableLogging = true,
  }) {
    if (_singleton == null) {
      _singleton =
          PusherClient._(appKey, options, enableLogging: enableLogging);
    }

    final initArgs = _InitArgs(enableLogging: enableLogging);

    _singleton._init(appKey, options, initArgs);

    _singleton.connect();

    return _singleton;
  }

  Future _init(String appKey, PusherOptions options, _InitArgs initArgs) async {
    _singleton._eventStreamSubscription =
        _eventStream.receiveBroadcastStream().listen(eventHandler);
    await _channel.invokeMethod('init', {
      'appKey': appKey,
      'pusherOptions': jsonEncode(options),
      'initArgs': jsonEncode(initArgs),
    });
  }

  Channel subscribe(String channelName) {
    return Channel(channelName);
  }

  Future<void> unsubscribe(String channelName) async {
    await _channel.invokeMethod('unsubscribe', {
      'channelName': channelName,
    });
  }

  Future connect() async {
    await _channel.invokeMethod('connect');
  }

  Future disconnect() async {
    await _channel.invokeMethod('disconnect');

    _eventStreamSubscription.cancel();
  }

  String getSocketId() => _socketId;

  void onConnectionStateChange(
      void Function(ConnectionStateChange state) callback) {
    _onConnectionStateChange = callback;
  }

  void onConnectionError(void Function(ConnectionError error) callback) {
    _onConnectionError = callback;
  }

  Future<void> eventHandler(event) async {
    var result = EventStreamResult.fromJson(jsonDecode(event.toString()));

    if (result.isConnectionStateChange) {
      _socketId = await _channel.invokeMethod('getSocketId');

      if (_onConnectionStateChange != null)
        _onConnectionStateChange(result.connectionStateChange);
    }

    if (result.isConnectionError) {
      if (_onConnectionError != null)
        _onConnectionError(result.connectionError);
    }
  }
}

@JsonSerializable()
class _InitArgs {
  final bool enableLogging;

  _InitArgs({
    this.enableLogging,
  });

  Map<String, dynamic> toJson() => _$_InitArgsToJson(this);
}
