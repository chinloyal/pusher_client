import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Minimal typed bindings for the pusher-js 8.x API used by the plugin.
///
/// Verified against pusher-js 8.4.0 (`dist/web/pusher-with-encryption.js`).

/// `new Pusher(key, options)`.
@JS('Pusher')
extension type PusherJs._(JSObject _) implements JSObject {
  external factory PusherJs(String key, JSObject options);

  external void connect();
  external void disconnect();
  external ChannelJs subscribe(String channelName);
  external void unsubscribe(String channelName);
  external ChannelJs? channel(String channelName);
  external ConnectionJs get connection;
}

/// `pusher.connection`.
extension type ConnectionJs._(JSObject _) implements JSObject {
  external void bind(String eventName, JSFunction callback);
  external void unbind([String? eventName, JSFunction? callback]);
  // ignore: non_constant_identifier_names
  external String? get socket_id;
  external String? get state;
}

/// A pusher-js channel (public, private, encrypted or presence).
extension type ChannelJs._(JSObject _) implements JSObject {
  // ignore: non_constant_identifier_names
  external void bind_global(JSFunction callback);
  // ignore: non_constant_identifier_names
  external void unbind_global([JSFunction? callback]);
  external bool trigger(String eventName, JSAny? data);

  /// The internal dispatcher `emit(eventName, data, metadata)`.
  external JSFunction get emit;
  external set emit(JSFunction value);

  /// Presence channels only.
  external MembersJs? get members;
}

/// `PresenceChannel.members`.
extension type MembersJs._(JSObject _) implements JSObject {
  external int get count;
  external void each(JSFunction callback);
}

/// Whether `globalThis.Pusher` is defined.
bool get isPusherJsLoaded => globalContext.has('Pusher');
