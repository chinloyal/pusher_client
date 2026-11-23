import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'auth.dart';
import 'channel.dart';
import 'models.dart';
import 'options.dart';
import 'platform/pusher_platform.dart';

/// The main entry point for accessing Pusher.
///
/// Creating a [PusherClient] initialises a native (or web) Pusher instance and
/// connects automatically unless `autoConnect` is `false`, in which case call
/// [connect] later. Every client owns its own instance; call [dispose] when
/// done.
class PusherClient implements ChannelHost {
  /// Creates a client for [appKey].
  ///
  /// Throws an [ArgumentError] if `options.host` is not a bare hostname (it
  /// contains `://`, `/` or `:`). Native failures during initialisation or
  /// connect are reported through [onConnectionError], never thrown.
  PusherClient(
    this.appKey,
    this.options, {
    bool enableLogging = false,
    bool autoConnect = true,
  })  : _enableLogging = enableLogging,
        _auth = options.auth,
        _instanceId = _nextInstanceId() {
    final host = options.host;
    if (host != null &&
        (host.contains('://') || host.contains('/') || host.contains(':'))) {
      throw ArgumentError.value(
        host,
        'options.host',
        'Must be a bare hostname without scheme, port or path',
      );
    }
    _ensureWired();
    _registry[_instanceId] = this;
    _tail = _initialize();
    if (autoConnect) unawaited(_connectNative());
  }

  /// The Pusher application key.
  final String appKey;

  /// The options this client was created with.
  final PusherOptions options;

  final bool _enableLogging;
  final String _instanceId;
  PusherAuth? _auth;
  late Future<void> _tail;
  bool _disposed = false;
  String _connectionState = 'DISCONNECTED';
  String? _socketId;
  final Map<String, Channel> _channels = {};
  void Function(ConnectionStateChange state)? _onStateChange;
  void Function(ConnectionError error)? _onError;
  final StreamController<ConnectionStateChange> _stateController =
      StreamController<ConnectionStateChange>.broadcast();
  final StreamController<ConnectionError> _errorController =
      StreamController<ConnectionError>.broadcast();

  // ---- static state (per isolate) -----------------------------------------

  static final Map<String, PusherClient> _registry = {};
  static final String _isolateId =
      Random().nextInt(0x7fffffff).toRadixString(36);
  static int _counter = 0;
  static StreamSubscription<Map<String, Object?>>? _eventsSubscription;
  static PusherPlatform? _wiredPlatform;
  static Completer<void>? _disposeAllDone;

  static String _nextInstanceId() => '$_isolateId-${++_counter}';

  static void _ensureWired() {
    if (_eventsSubscription != null) return;
    final platform = _wiredPlatform = PusherPlatform.instance;
    _eventsSubscription = platform.events.listen(
      _dispatchEvent,
      onError: (_) {},
    );
    platform.authorizeHandler = _dispatchAuthorize;
  }

  static void _dispatchEvent(Map<String, Object?> event) {
    final id = event['instanceId'];
    final client = id is String ? _registry[id] : null;
    client?._handleEvent(event);
  }

  static Future<Map<String, Object?>> _dispatchAuthorize(
    String instanceId,
    String channelName,
    String socketId,
  ) {
    final client = _registry[instanceId];
    if (client == null) {
      return Future.error(authError('Unknown instance $instanceId'));
    }
    return client._authorize(channelName, socketId);
  }

  /// Clears all static state. Only for tests.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _wiredPlatform?.authorizeHandler = null;
    _wiredPlatform = null;
    for (final client in _registry.values) {
      await client._stateController.close();
      await client._errorController.close();
    }
    _registry.clear();
    _disposeAllDone = null;
    _counter = 0;
  }

  // ---- native call plumbing ------------------------------------------------

  /// Runs [op] after every previously enqueued native call completed.
  Future<T> _enqueue<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _initialize() async {
    try {
      final platform = PusherPlatform.instance;
      if (_disposeAllDone == null) {
        final done = _disposeAllDone = Completer<void>();
        try {
          await platform.disposeAll();
        } catch (e) {
          _reportNativeError(e);
        } finally {
          done.complete();
        }
      } else {
        await _disposeAllDone!.future;
      }
      await platform.init(_instanceId, appKey, options.toMap(), _enableLogging);
    } catch (e) {
      _reportNativeError(e);
    }
  }

  Future<void> _connectNative() async {
    try {
      await _enqueue(() => PusherPlatform.instance.connect(_instanceId));
    } catch (e) {
      _reportNativeError(e);
    }
  }

  void _reportNativeError(Object error) {
    if (_disposed) return;
    final ConnectionError converted;
    if (error is PlatformException) {
      converted = ConnectionError(
        message: error.message ?? error.code,
        code: error.code,
        exception: error.toString(),
      );
    } else {
      converted = ConnectionError(
        message: error.toString(),
        exception: error.toString(),
      );
    }
    _log('Native call failed: $error');
    _emitError(converted);
  }

  void _emitError(ConnectionError error) {
    final callback = _onError;
    if (callback != null) {
      try {
        callback(error);
      } catch (e) {
        _log('onConnectionError callback threw: $e');
      }
    }
    if (!_errorController.isClosed) _errorController.add(error);
  }

  void _emitStateChange(ConnectionStateChange change) {
    final callback = _onStateChange;
    if (callback != null) {
      try {
        callback(change);
      } catch (e) {
        _log('onConnectionStateChange callback threw: $e');
      }
    }
    if (!_stateController.isClosed) _stateController.add(change);
  }

  void _log(String message) {
    if (_enableLogging) developer.log(message, name: 'pusher_client');
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('This PusherClient has been disposed.');
    }
  }

  // ---- ChannelHost ----------------------------------------------------------

  @override
  bool get enableLogging => _enableLogging;

  @override
  void ensureUsable() => _ensureUsable();

  @override
  Future<void> triggerEvent(
    String channelName,
    String eventName,
    String data,
  ) =>
      _enqueue(
        () => PusherPlatform.instance.trigger(
          _instanceId,
          channelName,
          eventName,
          data,
        ),
      );

  // ---- events ---------------------------------------------------------------

  void _handleEvent(Map<String, Object?> map) {
    if (_disposed) return;
    switch (map['type']) {
      case 'connectionStateChange':
        final change = ConnectionStateChange.fromMap(map);
        _connectionState = change.currentState ?? _connectionState;
        final socketId = map['socketId'];
        _socketId = socketId is String ? socketId : null;
        _emitStateChange(change);
      case 'connectionError':
        _emitError(ConnectionError.fromMap(map));
      case 'event':
        final event = PusherEvent.fromMap(map);
        _channels[event.channelName]?.handleEvent(event);
      default:
        _log('Ignoring unknown event type ${map['type']}');
    }
  }

  Future<Map<String, Object?>> _authorize(
    String channelName,
    String socketId,
  ) async {
    try {
      final PusherAuthorizationData data;
      final authorizer = options.authorizer;
      final auth = _auth;
      if (authorizer != null) {
        data = await authorizer(channelName, socketId);
      } else if (auth != null) {
        data = await HttpAuthorizer.authorize(auth, channelName, socketId);
      } else {
        throw authError(
          'No authorizer configured. Set PusherOptions.auth or '
          'PusherOptions.authorizer.',
        );
      }
      final channel = _channels[channelName];
      if (channel is PresenceChannel) channel.updateMe(data.channelData);
      return data.toMap();
    } on PlatformException {
      rethrow;
    } catch (e) {
      _log('Authorization of $channelName failed: $e');
      throw authError(e is PusherException ? e.message : e.toString());
    }
  }

  // ---- public API -------------------------------------------------------------

  /// Initiates a connection attempt using the client's existing connection
  /// details. Failures are reported through [onConnectionError].
  Future<void> connect() async {
    _ensureUsable();
    await _connectNative();
  }

  /// Disconnects the client's connection. Subscriptions are kept; [connect]
  /// resumes them.
  Future<void> disconnect() async {
    _ensureUsable();
    await _enqueue(() => PusherPlatform.instance.disconnect(_instanceId));
  }

  /// Disconnects and releases the native instance. The client cannot be used
  /// afterwards: every other member throws a [StateError]. Calling [dispose]
  /// again does nothing.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _registry.remove(_instanceId);
    _channels.clear();
    _onStateChange = null;
    _onError = null;
    try {
      await _enqueue(() => PusherPlatform.instance.dispose(_instanceId));
    } catch (e) {
      _log('dispose failed: $e');
    }
    await _stateController.close();
    await _errorController.close();
  }

  /// Subscribes the client to a channel and returns it (a [PresenceChannel]
  /// for `presence-` names).
  ///
  /// Subscriptions are persisted over disconnection and re-registered with the
  /// server automatically on reconnection, and may be registered before
  /// [connect] is called. Subscribing to an already subscribed name returns
  /// the same object. If the previous attempt failed with
  /// `pusher:subscription_error` (for example an auth error), calling
  /// [subscribe] again retries the subscription and returns the same object.
  Channel subscribe(String channelName) {
    _ensureUsable();
    final existing = _channels[channelName];
    if (existing != null && !existing.subscriptionFailed) return existing;
    final channel = existing ??
        (channelName.startsWith('presence-')
            ? PresenceChannel(channelName, this)
            : Channel(channelName, this));
    _channels[channelName] = channel;
    unawaited(
      _enqueue(
        () => PusherPlatform.instance.subscribe(_instanceId, channelName),
      ).then<void>((_) {}, onError: (Object e) => _reportNativeError(e)),
    );
    return channel;
  }

  /// Unsubscribes from a channel using the name of the channel.
  Future<void> unsubscribe(String channelName) async {
    _ensureUsable();
    final channel = _channels.remove(channelName);
    if (channel == null) return;
    channel.markUnsubscribed();
    await _enqueue(
      () => PusherPlatform.instance.unsubscribe(_instanceId, channelName),
    );
  }

  /// The subscribed channel with this name, or `null`.
  Channel? channel(String channelName) {
    _ensureUsable();
    return _channels[channelName];
  }

  /// The subscribed channels by name (unmodifiable view).
  Map<String, Channel> get channels {
    _ensureUsable();
    return Map.unmodifiable(_channels);
  }

  /// The id of the current connection, or `null` when not connected.
  String? getSocketId() => socketId;

  /// The id of the current connection, or `null` when not connected.
  String? get socketId {
    _ensureUsable();
    return _socketId;
  }

  /// The current connection state: `CONNECTING`, `CONNECTED`,
  /// `DISCONNECTING`, `DISCONNECTED` (initially) or `RECONNECTING`.
  String get connectionState {
    _ensureUsable();
    return _connectionState;
  }

  /// Sets the callback fired whenever the connection state changes, replacing
  /// a previous one. The state typically changes during connection to Pusher
  /// and during disconnection and reconnection.
  void onConnectionStateChange(
    void Function(ConnectionStateChange state) callback,
  ) {
    _ensureUsable();
    _onStateChange = callback;
  }

  /// Sets the callback fired when either an error message has been received
  /// from Pusher or an error occurred in the client library (including failed
  /// native calls), replacing a previous one.
  void onConnectionError(void Function(ConnectionError error) callback) {
    _ensureUsable();
    _onError = callback;
  }

  /// Broadcast stream of connection state changes.
  Stream<ConnectionStateChange> get connectionStateChanges {
    _ensureUsable();
    return _stateController.stream;
  }

  /// Broadcast stream of connection errors.
  Stream<ConnectionError> get connectionErrors {
    _ensureUsable();
    return _errorController.stream;
  }

  /// Replaces the [PusherAuth] used for future channel authorizations, for
  /// example to refresh a bearer token. Has no effect when
  /// [PusherOptions.authorizer] is set.
  void updateAuth(PusherAuth auth) {
    _ensureUsable();
    _auth = auth;
  }
}
