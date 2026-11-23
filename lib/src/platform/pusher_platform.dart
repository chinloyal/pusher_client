import 'method_channel_platform.dart';

/// Handles an `authorize` request coming from the platform layer.
typedef AuthorizeHandler = Future<Map<String, Object?>> Function(
  String instanceId,
  String channelName,
  String socketId,
);

/// The platform abstraction. Implemented by [MethodChannelPusherPlatform] on
/// Android, iOS and macOS and by the web implementation on the web.
///
/// Internal: not exported by the package.
abstract class PusherPlatform {
  /// The implementation in use.
  static PusherPlatform instance = MethodChannelPusherPlatform();

  /// All events of all instances (broadcast).
  Stream<Map<String, Object?>> get events;

  /// Called when the platform needs a channel authorization.
  set authorizeHandler(AuthorizeHandler? handler);

  /// Disconnects and drops every native instance.
  Future<void> disposeAll();

  /// Creates the native instance for [instanceId]; does not connect.
  Future<void> init(
    String instanceId,
    String appKey,
    Map<String, Object?> options,
    bool enableLogging,
  );

  /// Connects the instance.
  Future<void> connect(String instanceId);

  /// Disconnects the instance, keeping its subscriptions.
  Future<void> disconnect(String instanceId);

  /// Releases the native instance.
  Future<void> dispose(String instanceId);

  /// Subscribes to a channel.
  Future<void> subscribe(String instanceId, String channelName);

  /// Unsubscribes from a channel.
  Future<void> unsubscribe(String instanceId, String channelName);

  /// Triggers a client event.
  Future<void> trigger(
    String instanceId,
    String channelName,
    String eventName,
    String data,
  );

  /// Returns the current socket id, if connected.
  Future<String?> getSocketId(String instanceId);
}
