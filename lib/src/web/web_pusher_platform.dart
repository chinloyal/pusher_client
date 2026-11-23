import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../platform/pusher_platform.dart';
import 'pusher_js_interop.dart';
import 'web_conversions.dart';

/// The pinned pusher-js build (with private-encrypted support) loaded when the
/// host page did not include pusher-js itself.
const String defaultPusherJsUrl =
    'https://js.pusher.com/8.4.0/pusher-with-encryption.min.js';

/// [PusherPlatform] implemented on top of pusher-js.
class WebPusherPlatform extends PusherPlatform {
  /// Creates the platform. [scriptUrl] can be overridden for tests.
  WebPusherPlatform({String scriptUrl = defaultPusherJsUrl})
      : _scriptUrl = scriptUrl;

  final String _scriptUrl;
  final StreamController<Map<String, Object?>> _events =
      StreamController<Map<String, Object?>>.broadcast();
  final Map<String, _Instance> _instances = {};
  AuthorizeHandler? _authorizeHandler;
  Future<void>? _loading;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  set authorizeHandler(AuthorizeHandler? handler) {
    _authorizeHandler = handler;
  }

  /// Loads pusher-js unless `globalThis.Pusher` already exists.
  Future<void> _ensureLoaded() {
    if (isPusherJsLoaded) return Future<void>.value();
    return _loading ??= _loadScript().catchError((Object e) {
      _loading = null;
      throw e;
    });
  }

  Future<void> _loadScript() {
    final completer = Completer<void>();
    final script = web.document.createElement('script') as web.HTMLScriptElement
      ..src = _scriptUrl
      ..async = true;
    script.addEventListener(
      'load',
      ((web.Event _) {
        if (isPusherJsLoaded) {
          completer.complete();
        } else {
          completer.completeError(StateError(
            'pusher-js loaded from $_scriptUrl but window.Pusher is undefined',
          ));
        }
      }).toJS,
    );
    script.addEventListener(
      'error',
      ((web.Event _) {
        script.remove();
        completer.completeError(
          StateError('Failed to load pusher-js from $_scriptUrl'),
        );
      }).toJS,
    );
    web.document.head!.append(script);
    return completer.future;
  }

  _Instance _get(String instanceId) {
    final instance = _instances[instanceId];
    if (instance == null) {
      throw PlatformException(
        code: 'NO_INSTANCE',
        message: 'No Pusher instance for id $instanceId',
      );
    }
    return instance;
  }

  @override
  Future<void> disposeAll() async {
    for (final instance in _instances.values.toList()) {
      instance.dispose();
    }
    _instances.clear();
  }

  @override
  Future<void> init(
    String instanceId,
    String appKey,
    Map<String, Object?> options,
    bool enableLogging,
  ) async {
    try {
      await _ensureLoaded();
      _instances.remove(instanceId)?.dispose();
      _instances[instanceId] = _Instance(
        instanceId,
        appKey,
        options,
        _events.add,
        (channelName, socketId) {
          final handler = _authorizeHandler;
          if (handler == null) {
            return Future.error(PlatformException(
              code: 'AUTH_ERROR',
              message: 'No authorize handler registered',
            ));
          }
          return handler(instanceId, channelName, socketId);
        },
      );
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'INIT_ERROR', message: e.toString());
    }
  }

  @override
  Future<void> connect(String instanceId) async {
    await _ensureLoaded();
    _get(instanceId).pusher.connect();
  }

  @override
  Future<void> disconnect(String instanceId) async {
    await _ensureLoaded();
    _get(instanceId).pusher.disconnect();
  }

  @override
  Future<void> dispose(String instanceId) async {
    _instances.remove(instanceId)?.dispose();
  }

  @override
  Future<void> subscribe(String instanceId, String channelName) async {
    await _ensureLoaded();
    final instance = _get(instanceId);
    try {
      instance.subscribe(channelName);
    } catch (e) {
      throw PlatformException(code: 'SUBSCRIBE_ERROR', message: e.toString());
    }
  }

  @override
  Future<void> unsubscribe(String instanceId, String channelName) async {
    await _ensureLoaded();
    final instance = _get(instanceId);
    try {
      instance.unsubscribe(channelName);
    } catch (e) {
      throw PlatformException(
        code: 'UNSUBSCRIBE_ERROR',
        message: e.toString(),
      );
    }
  }

  @override
  Future<void> trigger(
    String instanceId,
    String channelName,
    String eventName,
    String data,
  ) async {
    await _ensureLoaded();
    final instance = _get(instanceId);
    if (!canTriggerOn(channelName)) {
      throw PlatformException(
        code: 'TRIGGER_ERROR',
        message: 'Client events can only be triggered on private and '
            'presence channels: $channelName',
      );
    }
    final channel = instance.pusher.channel(channelName);
    if (channel == null) {
      throw PlatformException(
        code: 'TRIGGER_ERROR',
        message: 'Not subscribed to $channelName',
      );
    }
    try {
      // The data string is passed through unchanged (as a JSON string value).
      channel.trigger(eventName, data.toJS);
    } catch (e) {
      throw PlatformException(code: 'TRIGGER_ERROR', message: e.toString());
    }
  }

  @override
  Future<String?> getSocketId(String instanceId) async {
    await _ensureLoaded();
    return _get(instanceId).pusher.connection.socket_id;
  }
}

/// One pusher-js instance plus its bindings.
class _Instance {
  _Instance(
    this.instanceId,
    String appKey,
    Map<String, Object?> options,
    this._emit,
    this._authorize,
  ) {
    final jsOptions = buildPusherJsOptions(options).jsify() as JSObject;
    jsOptions['channelAuthorization'] = <String, Object?>{
      'customHandler': _customHandler.toJS,
    }.jsify();
    pusher = PusherJs(appKey, jsOptions);
    pusher.connection.bind('state_change', _onStateChange.toJS);
    pusher.connection.bind('error', _onError.toJS);
  }

  final String instanceId;
  final void Function(Map<String, Object?>) _emit;
  final Future<Map<String, Object?>> Function(
    String channelName,
    String socketId,
  ) _authorize;
  late final PusherJs pusher;

  /// Channels whose global listener is bound: name -> (channel, listener).
  final Map<String, (ChannelJs, JSFunction)> _bound = {};

  /// AUTH_ERROR status remembered per channel (pusher-js only reports a status
  /// for its built-in HTTP authorizer).
  final Map<String, int?> _authStatus = {};

  bool _disposed = false;

  // ---- connection ---------------------------------------------------------

  void _onStateChange(JSAny? change) {
    if (_disposed) return;
    final event = buildConnectionStateEvent(
      instanceId,
      _stringProp(change, 'previous'),
      _stringProp(change, 'current'),
      pusher.connection.socket_id,
    );
    if (event != null) _emit(event);
  }

  void _onError(JSAny? error) {
    if (_disposed) return;
    final inner = _prop(error, 'error');
    final data = _prop(inner, 'data');
    final message = _stringProp(data, 'message') ??
        _stringProp(inner, 'message') ??
        _stringProp(error, 'message') ??
        _stringProp(error, 'type');
    final code = _prop(data, 'code') ?? _prop(inner, 'code');
    _emit(buildConnectionErrorEvent(
      instanceId,
      message: message,
      code: code.dartify(),
      exception: _stringProp(error, 'type'),
    ));
  }

  // ---- authorization ------------------------------------------------------

  void _customHandler(JSObject params, JSFunction callback) {
    final channelName = _stringProp(params, 'channelName') ?? '';
    final socketId = _stringProp(params, 'socketId') ?? '';
    _authorize(channelName, socketId).then<void>((authorization) {
      _authStatus.remove(channelName);
      callback.callAsFunction(
        null,
        null,
        buildAuthResult(authorization).jsify(),
      );
    }, onError: (Object e) {
      var message = e.toString();
      int? status;
      if (e is PlatformException) {
        message = e.message ?? e.code;
        status = authStatusFromDetails(e.details);
      }
      _authStatus[channelName] = status;
      final errorCtor = globalContext['Error'] as JSFunction;
      final error = errorCtor.callAsConstructor<JSObject>(message.toJS);
      callback.callAsFunction(null, error, null);
    });
  }

  // ---- channels -----------------------------------------------------------

  void subscribe(String channelName) {
    final channel = pusher.subscribe(channelName);
    if (_bound.containsKey(channelName)) return;
    String? lastUserId;
    // pusher-js global callbacks only receive (eventName, data); wrap emit to
    // capture the metadata (client-event user_id) for the callback.
    final originalEmit = channel.emit;
    channel.emit = ((JSAny? name, [JSAny? data, JSAny? meta]) {
      final id = _prop(meta, 'user_id').dartify();
      lastUserId = id?.toString();
      try {
        originalEmit.callAsFunction(channel, name, data, meta);
      } finally {
        lastUserId = null;
      }
    }).toJS;
    final listener = ((JSAny? name, JSAny? data) {
      if (_disposed || !name.isA<JSString>()) return;
      _onChannelEvent(
        channelName,
        (name as JSString).toDart,
        data,
        lastUserId,
        channel,
      );
    }).toJS;
    channel.bind_global(listener);
    _bound[channelName] = (channel, listener);
  }

  void unsubscribe(String channelName) {
    final bound = _bound.remove(channelName);
    bound?.$1.unbind_global(bound.$2);
    _authStatus.remove(channelName);
    pusher.unsubscribe(channelName);
  }

  void _onChannelEvent(
    String channelName,
    String eventName,
    JSAny? data,
    String? metaUserId,
    ChannelJs channel,
  ) {
    if (isInternalEvent(eventName)) return;
    String? payload;
    String? userId = metaUserId;
    switch (eventName) {
      case 'pusher:subscription_succeeded':
        payload = isPresenceChannel(channelName)
            ? _presenceData(channel, data)
            : '{}';
      case 'pusher:subscription_error':
        payload = normalizeSubscriptionError(
          _toJson(data),
          fallbackStatus: _authStatus.remove(channelName),
        );
      case 'pusher:member_added':
        final member = _toJson(data);
        if (member is! Map) return;
        userId = member['id']?.toString();
        payload = memberAddedData(userId ?? '', member['info']);
      case 'pusher:member_removed':
        final member = _toJson(data);
        if (member is! Map) return;
        userId = member['id']?.toString();
        payload = memberRemovedData(userId ?? '');
      case 'pusher:subscription_count':
        final count = _toJson(data);
        final n = count is Map ? count['subscription_count'] : null;
        payload = subscriptionCountData(n is num ? n.toInt() : 0);
      default:
        payload = _stringify(data);
    }
    _emit(buildChannelEvent(
      instanceId,
      channelName,
      eventName,
      payload,
      userId: userId,
    ));
  }

  String _presenceData(ChannelJs channel, JSAny? data) {
    final members = data.isA<JSObject>()
        ? (data as JSObject) as MembersJs
        : channel.members;
    final hash = <String, Object?>{};
    var count = 0;
    if (members != null) {
      count = members.count;
      members.each(((JSAny? member) {
        final id = _prop(member, 'id').dartify();
        if (id == null) return;
        hash[id.toString()] = _toJson(_prop(member, 'info'));
      }).toJS);
    }
    return presenceSubscriptionData(hash, count: count);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _bound.entries) {
      try {
        entry.value.$1.unbind_global(entry.value.$2);
        pusher.unsubscribe(entry.key);
      } catch (_) {}
    }
    _bound.clear();
    try {
      pusher.connection.unbind();
      pusher.disconnect();
    } catch (_) {}
  }
}

// ---- tiny JS helpers --------------------------------------------------------

JSAny? _prop(JSAny? object, String key) {
  if (object == null || !object.isA<JSObject>()) return null;
  return (object as JSObject)[key];
}

String? _stringProp(JSAny? object, String key) {
  final value = _prop(object, key);
  if (value == null) return null;
  if (value.isA<JSString>()) return (value as JSString).toDart;
  return value.dartify()?.toString();
}

/// `JSON.stringify` for non-strings, the string itself for strings.
String? _stringify(JSAny? value) {
  if (value == null) return null;
  if (value.isA<JSString>()) return (value as JSString).toDart;
  return _jsonStringify(value);
}

String? _jsonStringify(JSAny? value) {
  final json = globalContext['JSON'] as JSObject;
  final result = json.callMethod<JSAny?>('stringify'.toJS, value);
  return result.isA<JSString>() ? (result as JSString).toDart : null;
}

/// Converts a JS value to plain Dart JSON data via `JSON.stringify`.
Object? _toJson(JSAny? value) {
  if (value == null) return null;
  final text = _jsonStringify(value);
  if (text == null) return null;
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}
