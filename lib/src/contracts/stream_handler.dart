import 'dart:async';

import 'package:flutter/services.dart';

abstract class StreamHandler {
  static const EventChannel _eventStream = const EventChannel('com.github.chinloyal/pusher_client_stream');
  late StreamSubscription _eventStreamSubscription;

  static Map<String, dynamic Function(dynamic)> _listeners = {};

  /// Add a listener to the event channel stream for pusher,
  /// any class that extends [StreamHandler] should use this method.
  void registerListener(String classId, dynamic Function(dynamic) method) {
    StreamHandler._listeners[classId] = method;
    _eventStreamSubscription = _eventStream.receiveBroadcastStream().listen(_eventHandler);
  }

  /// This method will close the entire event channel stream
  /// which is why it should only be used by [PusherClient]
  void cancelEventChannelStream() {
    _eventStreamSubscription.cancel();
  }

  void _eventHandler(event) {
    _listeners.values.forEach((method) {
      method(event);
    });
  }
}
