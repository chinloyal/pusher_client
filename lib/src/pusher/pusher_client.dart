import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pusher_client/pusher_client.dart';
import 'package:pusher_client/src/contracts/stream_handler.dart';
import 'package:pusher_client/src/models/connection_error.dart';
import 'package:pusher_client/src/models/connection_state_change.dart';
import 'package:pusher_client/src/models/event_stream_result.dart';
import 'package:pusher_client/src/pusher/channel.dart';

part 'pusher_client.g.dart';

/// This class is the main entry point for accessing Pusher.
/// By creating a new [PusherClient] instance a connection is
/// created automatically unless [autoConnect] is set to false,
/// if auto connect is disabled this means you can call
/// `connect()` at a later point.
class PusherClient extends StreamHandler {
  static const MethodChannel _channel =
      const MethodChannel('com.github.chinloyal/pusher_client');
  static const classId = 'PusherClient';

  static PusherClient? _singleton;
  void Function(ConnectionStateChange?)? _onConnectionStateChange;
  void Function(ConnectionError?)? _onConnectionError;
  String? _socketId;

  PusherClient._(
    String appKey,
    PusherOptions options, {
    bool enableLogging = true,
    bool autoConnect = true,
  });

  /// Creates a [PusherClient] -- returns the instance if it's already be called.
  factory PusherClient(
    String appKey,
    PusherOptions options, {
    bool enableLogging = true,
    bool autoConnect = true,
  }) {
    _singleton ??= PusherClient._(
      appKey,
      options,
      enableLogging: enableLogging,
      autoConnect: autoConnect,
    );

    final initArgs = InitArgs(enableLogging: enableLogging);

    _singleton!._init(appKey, options, initArgs);

    if (autoConnect) _singleton!.connect();

    return _singleton!;
  }

  Future _init(String appKey, PusherOptions options, InitArgs initArgs) async {
    registerListener(classId, _eventHandler);
    await _channel.invokeMethod(
      'init',
      jsonEncode({
        'appKey': appKey,
        'pusherOptions': options,
        'initArgs': initArgs,
      }),
    );
  }

  /// Subscribes the client to a new channel
  ///
  /// Note that subscriptions should be registered only once with a Pusher
  /// instance. Subscriptions are persisted over disconnection and
  /// re-registered with the server automatically on reconnection. This means
  /// that subscriptions may also be registered before `connect()` is called,
  /// they will be initiated on connection.
  Channel subscribe(String channelName) {
    return Channel(channelName);
  }

  /// Unsubscribes from a channel using the name of the channel.
  Future<void> unsubscribe(String channelName) async {
    await _channel.invokeMethod('unsubscribe', {
      'channelName': channelName,
    });
  }

  /// Initiates a connection attempt using the client's
  /// existing connection details
  Future connect() async {
    await _channel.invokeMethod('connect');
  }

  /// Disconnects the client's connection
  Future disconnect() async {
    await _channel.invokeMethod('disconnect');

    cancelEventChannelStream();
  }

  /// The id of the current connection
  String? getSocketId() => _socketId;

  /// Callback that is fired whenever the connection state of the
  /// connection changes. The state typically changes during connection
  /// to Pusher and during disconnection and reconnection.
  void onConnectionStateChange(
      void Function(ConnectionStateChange? state) callback) {
    _onConnectionStateChange = callback;
  }

  /// Callback that indicates either:
  /// - An error message has been received from Pusher, or
  /// - An error has occurred in the client library.
  void onConnectionError(void Function(ConnectionError? error) callback) {
    _onConnectionError = callback;
  }

  Future<void> _eventHandler(event) async {
    var result = EventStreamResult.fromJson(jsonDecode(event.toString()));

    if (result.isConnectionStateChange) {
      _socketId = await _channel.invokeMethod('getSocketId');

      if (_onConnectionStateChange != null)
        _onConnectionStateChange!(result.connectionStateChange);
    }

    if (result.isConnectionError) {
      if (_onConnectionError != null)
        _onConnectionError!(result.connectionError);
    }
  }
}

class InitArgs {
  final bool? enableLogging;

  InitArgs({
    this.enableLogging,
  });

  Map<String, dynamic> toJson() => _$InitArgsToJson(this);
}
