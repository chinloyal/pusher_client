import 'dart:async';

import 'package:pusher_client/src/platform/pusher_platform.dart';
import 'package:pusher_client/src/pusher_client.dart';

/// A recorded platform call.
class Call {
  Call(this.method, this.args);
  final String method;
  final List<Object?> args;

  @override
  String toString() => '$method($args)';
}

class FakePlatform extends PusherPlatform {
  final controller = StreamController<Map<String, Object?>>.broadcast();
  final calls = <Call>[];
  final failures = <String, Object>{};
  final gates = <String, Completer<void>>{};
  AuthorizeHandler? handler;
  String? socketIdResult;

  @override
  Stream<Map<String, Object?>> get events => controller.stream;

  @override
  set authorizeHandler(AuthorizeHandler? h) => handler = h;

  Future<void> _record(String method, [List<Object?> args = const []]) async {
    calls.add(Call(method, args));
    final gate = gates[method];
    if (gate != null) await gate.future;
    final failure = failures[method];
    if (failure != null) throw failure;
  }

  List<String> get methods => calls.map((c) => c.method).toList();

  void emit(Map<String, Object?> event) => controller.add(event);

  @override
  Future<void> disposeAll() => _record('disposeAll');

  @override
  Future<void> init(
    String instanceId,
    String appKey,
    Map<String, Object?> options,
    bool enableLogging,
  ) =>
      _record('init', [instanceId, appKey, options, enableLogging]);

  @override
  Future<void> connect(String instanceId) => _record('connect', [instanceId]);

  @override
  Future<void> disconnect(String instanceId) =>
      _record('disconnect', [instanceId]);

  @override
  Future<void> dispose(String instanceId) => _record('dispose', [instanceId]);

  @override
  Future<void> subscribe(String instanceId, String channelName) =>
      _record('subscribe', [instanceId, channelName]);

  @override
  Future<void> unsubscribe(String instanceId, String channelName) =>
      _record('unsubscribe', [instanceId, channelName]);

  @override
  Future<void> trigger(
    String instanceId,
    String channelName,
    String eventName,
    String data,
  ) =>
      _record('trigger', [instanceId, channelName, eventName, data]);

  @override
  Future<String?> getSocketId(String instanceId) async {
    await _record('getSocketId', [instanceId]);
    return socketIdResult;
  }
}

/// Installs a fresh [FakePlatform] and resets the client's static state.
Future<FakePlatform> installFakePlatform() async {
  await PusherClient.resetForTesting();
  final fake = FakePlatform();
  PusherPlatform.instance = fake;
  return fake;
}

/// Lets queued microtasks and timers run.
Future<void> settle() => Future<void>.delayed(Duration.zero);
