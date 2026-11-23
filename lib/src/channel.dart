import 'dart:convert';
import 'dart:developer' as developer;

import 'package:meta/meta.dart';

import 'models.dart';

/// The services a channel needs from the client that owns it.
///
/// Internal: implemented by `PusherClient`.
abstract interface class ChannelHost {
  /// Whether diagnostics should be logged.
  bool get enableLogging;

  /// Throws a [StateError] if the owning client was disposed.
  void ensureUsable();

  /// Sends a client event through the platform layer.
  Future<void> triggerEvent(String channelName, String eventName, String data);
}

/// Callback receiving the events of a channel.
typedef PusherEventCallback = void Function(PusherEvent event);

/// A channel the client is subscribed to.
///
/// Obtain instances with `PusherClient.subscribe`; do not construct them
/// directly.
class Channel {
  /// Creates a channel owned by [host]. Internal: use
  /// `PusherClient.subscribe`.
  @internal
  Channel(this.name, ChannelHost host) : _host = host;

  /// The name of the channel.
  final String name;

  final ChannelHost _host;
  final Map<String, PusherEventCallback> _callbacks = {};
  PusherEventCallback? _globalCallback;
  bool _isSubscribed = false;
  bool _subscriptionFailed = false;
  int? _subscriptionCount;

  /// Whether the subscription is currently active: `true` after
  /// `pusher:subscription_succeeded`, `false` after an unsubscribe or a
  /// `pusher:subscription_error`.
  bool get isSubscribed => _isSubscribed;

  /// Internal: whether the last subscription attempt ended with
  /// `pusher:subscription_error` (the native library then forgets the
  /// channel, so subscribing again must be re-sent).
  @internal
  bool get subscriptionFailed => _subscriptionFailed;

  /// The number of subscribers, from `pusher:subscription_count`. Only
  /// available when the feature is enabled for the Pusher app.
  int? get subscriptionCount => _subscriptionCount;

  /// Binds a callback ([onEvent]) to an event. The callback is notified
  /// whenever the specified [eventName] is received on this channel.
  ///
  /// Binding the same [eventName] again replaces the previous callback.
  Future<void> bind(String eventName, PusherEventCallback onEvent) async {
    _host.ensureUsable();
    _callbacks[eventName] = onEvent;
  }

  /// Unbinds the callback from the given [eventName], in the scope of this
  /// channel.
  Future<void> unbind(String eventName) async {
    _host.ensureUsable();
    _callbacks.remove(eventName);
  }

  /// Binds a callback that is notified of every event on this channel,
  /// replacing a previous global callback.
  void bindGlobal(PusherEventCallback onEvent) {
    _host.ensureUsable();
    _globalCallback = onEvent;
  }

  /// Removes the callback set with [bindGlobal].
  void unbindGlobal() {
    _host.ensureUsable();
    _globalCallback = null;
  }

  /// Once subscribed it is possible to trigger client events on a private or
  /// presence channel, as long as client events have been activated for the
  /// Pusher application. For full details see the
  /// [documentation](https://pusher.com/docs/channels/using_channels/events/#triggering-client-events).
  ///
  /// The [eventName] gets a `client-` prefix if it has none. A [data] that is
  /// a `String` is sent as-is; anything else is JSON encoded.
  ///
  /// Throws a [PusherException] with code `TRIGGER_ERROR` if the channel is
  /// not a private or presence channel, or is not subscribed yet.
  Future<void> trigger(String eventName, dynamic data) async {
    _host.ensureUsable();
    final isPrivate =
        name.startsWith('private-') && !name.startsWith('private-encrypted-');
    if (!isPrivate && !name.startsWith('presence-')) {
      throw const PusherException(
        'Client events can only be triggered on private and presence '
        'channels.',
        code: 'TRIGGER_ERROR',
      );
    }
    if (!_isSubscribed) {
      throw PusherException(
        'Cannot trigger a client event before $name is subscribed.',
        code: 'TRIGGER_ERROR',
      );
    }
    final prefixed =
        eventName.startsWith('client-') ? eventName : 'client-$eventName';
    final String payload;
    if (data is String) {
      payload = data;
    } else {
      try {
        payload = jsonEncode(data);
      } on JsonUnsupportedObjectError catch (e) {
        throw PusherException(
          'Event data cannot be JSON encoded: $e',
          code: 'TRIGGER_ERROR',
        );
      }
    }
    await _host.triggerEvent(name, prefixed, payload);
  }

  /// Routes an event received from the platform. Internal.
  @internal
  void handleEvent(PusherEvent event) {
    _updateState(event);
    final specific = _callbacks[event.eventName];
    if (specific != null) _invoke(specific, event);
    final global = _globalCallback;
    if (global != null) _invoke(global, event);
  }

  /// Resets the subscription state after an unsubscribe. Internal.
  @internal
  void markUnsubscribed() {
    _isSubscribed = false;
    _subscriptionCount = null;
    onSubscriptionReset();
  }

  /// Hook for subclasses to clear state on unsubscribe or error.
  @internal
  void onSubscriptionReset() {}

  /// Hook for subclasses to react to an event before callbacks run.
  @internal
  void onEventReceived(PusherEvent event) {}

  /// Logs [message] when logging is enabled.
  @internal
  void log(String message) {
    if (_host.enableLogging) {
      developer.log(message, name: 'pusher_client');
    }
  }

  void _updateState(PusherEvent event) {
    switch (event.eventName) {
      case 'pusher:subscription_succeeded':
        _isSubscribed = true;
        _subscriptionFailed = false;
      case 'pusher:subscription_error':
        _isSubscribed = false;
        _subscriptionFailed = true;
        onSubscriptionReset();
      case 'pusher:subscription_count':
        final map = decodeJsonMap(event.data);
        final count = map?['subscription_count'];
        if (count is num) _subscriptionCount = count.toInt();
    }
    onEventReceived(event);
  }

  void _invoke(PusherEventCallback callback, PusherEvent event) {
    try {
      callback(event);
    } catch (e, s) {
      log('Callback for ${event.eventName} on $name threw: $e\n$s');
    }
  }

  /// Decodes [data] as a JSON object, or returns null. Internal.
  @internal
  static Map<String, dynamic>? decodeJsonMap(String? data) {
    if (data == null) return null;
    try {
      final decoded = jsonDecode(data);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } on FormatException {
      return null;
    }
  }
}

/// A presence channel. Tracks the members currently subscribed.
class PresenceChannel extends Channel {
  /// Creates a presence channel owned by [host]. Internal: use
  /// `PusherClient.subscribe` with a `presence-` name.
  @internal
  PresenceChannel(super.name, super.host);

  final Map<String, dynamic> _members = {};
  String? _me;

  /// The members of the channel: user id to user info (unmodifiable view).
  Map<String, dynamic> get members => Map.unmodifiable(_members);

  /// The number of members in the channel.
  int get memberCount => _members.length;

  /// The user id of the current user, taken from the `channel_data` of the
  /// authorization response, if known.
  String? get me => _me;

  /// Records the user id found in [channelData] (a JSON string). Internal.
  @internal
  void updateMe(String? channelData) {
    final userId = Channel.decodeJsonMap(channelData)?['user_id'];
    if (userId != null) _me = userId.toString();
  }

  @override
  void onSubscriptionReset() {
    _members.clear();
  }

  @override
  void markUnsubscribed() {
    super.markUnsubscribed();
    _me = null;
  }

  @override
  void onEventReceived(PusherEvent event) {
    switch (event.eventName) {
      case 'pusher:subscription_succeeded':
        final presence = Channel.decodeJsonMap(event.data)?['presence'];
        final hash = presence is Map ? presence['hash'] : null;
        _members.clear();
        if (hash is Map) {
          hash.forEach((k, v) => _members[k.toString()] = v);
        }
      case 'pusher:member_added':
        final map = Channel.decodeJsonMap(event.data);
        final id = map?['user_id'] ?? event.userId;
        if (id != null) _members[id.toString()] = map?['user_info'];
      case 'pusher:member_removed':
        final map = Channel.decodeJsonMap(event.data);
        final id = map?['user_id'] ?? event.userId;
        if (id != null) _members.remove(id.toString());
    }
  }
}
