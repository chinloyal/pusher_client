import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pusher_client/src/models/event_stream_result.dart';

class Channel {
  static const MethodChannel _mChannel =
      const MethodChannel('com.github.chinloyal/pusher_client');
  static const EventChannel _eventStream =
      const EventChannel('com.github.chinloyal/pusher_client_stream');

  Map<String, Function> _eventCallbacks = Map<String, Function>();
  StreamSubscription _eventStreamSubscription;

  final String name;

  Channel(this.name) {
    _subscribe();
  }

  void _subscribe() {
    _mChannel.invokeMethod('subscribe', {
      'channelName': name,
    });
  }

  Future<void> bind(
      String eventName, void Function(dynamic event) onEvent) async {
    _eventStreamSubscription =
        _eventStream.receiveBroadcastStream().listen(_eventHandler);
    _eventCallbacks[this.name + eventName] = onEvent;

    await _mChannel.invokeMethod('bind', {
      'channelName': this.name,
      'eventName': eventName,
    });
  }

  Future<void> unbind(String eventName) async {
    _eventCallbacks.remove(this.name + eventName);

    if (_eventCallbacks.isEmpty) {
      _eventStreamSubscription.cancel();
    }

    await _mChannel.invokeMethod('unbind', {
      'channelName': this.name,
      'eventName': eventName,
    });
  }

  Future<void> trigger(String eventName, dynamic data) async {
    if (!eventName.startsWith('client-')) {
      eventName = "client-$eventName";
    }

    await _mChannel.invokeMethod('trigger', {
      'eventName': eventName,
      'data': jsonEncode(data),
      'channelName': this.name,
    });
  }

  Future<void> _eventHandler(event) async {
    var result = EventStreamResult.fromJson(jsonDecode(event.toString()));

    if (result.isPusherEvent) {
      var callback = _eventCallbacks[
          result.pusherEvent.channelName + result.pusherEvent.eventName];
      if (callback != null) {
        callback(jsonDecode(result.pusherEvent.data));
      }
    }
  }
}
