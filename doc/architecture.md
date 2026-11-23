# pusher_client 3.0.0 — Architecture & Platform Protocol

This document is the single source of truth for how the Dart layer and the
native/web implementations talk to each other. Any change to the protocol must
be made here first, then in **every** implementation (Dart, Android, Darwin,
web) and their tests.

## 1. Goals of the 3.0.0 rewrite

| Problem in 2.x | 3.0.0 answer | Issues |
|---|---|---|
| Ancient Gradle/Kotlin/AGP, no `namespace`, `jcenter()` | Modern Gradle, namespace, compatible with AGP 8 and AGP 9 (built-in Kotlin on or off) | #48, #69, #79, #80, PRs 71–75, 83–86 |
| Deprecated `PusherSwiftWithEncryption` 8.0, iOS 9, libsodium arm64 sim breakage, Reachability clash, no privacy manifest | `PusherSwift ~> 10.1.10` (TweetNacl, NWWebSocket), iOS 13 / macOS 10.15, CocoaPods **and** Swift Package Manager, `PrivacyInfo.xcprivacy` | #6, #27, #32, #36, #46, #50, #51, #64–#67, #79, #81 |
| Singleton client + native `if (instance == null)` guard ⇒ auth token / options can never change | No singleton. Each `PusherClient` owns its own native instance (`instanceId`). `dispose()` releases it. | #10, #20, #61, #73 |
| Auth done natively, differently on each OS (JSON vs urlencoded, stale headers, silent failures) | **All channel authorization happens in Dart**: either a user `authorizer` callback or the built-in HTTP `PusherAuth`. Failures surface as `pusher:subscription_error` events. | #10, #22, #25, #28, #37, #45, #47, #78, PR 42 |
| `registerListener` re-subscribes to the EventChannel on every `bind` ⇒ lost/duplicate events | One shared EventChannel subscription per isolate; Dart routes events by `instanceId`/channel/event | #7, #26, #34, #38 |
| JSON-encoded strings over method channel; `data.toString()` on trigger | Standard codec maps; trigger JSON-encodes non-string data | #1, #43, #56 |
| iOS presence member events never fire; Android presence data is `Set.toString()` | Native emits protocol-shaped presence data; Dart maintains `PresenceChannel.members` | #2, #12, #29, #52 |
| Force-unwraps / double `result` replies crash the app | Native validates and replies exactly once; errors are `PlatformException`s with stable codes | #38, #43, #49, PR 53 |
| R8 strips pusher-java / gson classes in release | `consumer-rules.pro` shipped with the plugin | #3, #4, #14, #29 |
| `host` + `cluster` both set ⇒ cluster wins ⇒ "App key not in this cluster" for self-hosted servers | Same rule as pusher-js: explicit `host` wins; otherwise `cluster`; otherwise Pusher default | #22, #33, #37 |
| Only Android & iOS | Android, iOS, macOS (shared Darwin source), web (pusher-js) | #17, #40 |

## 2. Public Dart API (lib/pusher_client.dart exports)

```dart
// ---- Client -------------------------------------------------------------
class PusherClient {
  PusherClient(String appKey, PusherOptions options,
      {bool enableLogging = false, bool autoConnect = true});

  final String appKey;
  final PusherOptions options;

  Future<void> connect();
  Future<void> disconnect();            // keeps subscriptions; connect() resumes
  Future<void> dispose();               // disconnect + release native instance; instance unusable afterwards

  Channel subscribe(String channelName);           // returns PresenceChannel for "presence-" names.
                                                   // Subscribing to an already-subscribed name returns the same object;
                                                   // if its last attempt ended in pusher:subscription_error, subscribe is re-sent.
  Future<void> unsubscribe(String channelName);
  Channel? channel(String channelName);             // lookup, null if not subscribed
  Map<String, Channel> get channels;                // unmodifiable view

  String? getSocketId();                           // kept from 2.x; same as socketId
  String? get socketId;
  String get connectionState;                      // "DISCONNECTED" initially, see §4.3

  void onConnectionStateChange(void Function(ConnectionStateChange state) callback);
  void onConnectionError(void Function(ConnectionError error) callback);
  Stream<ConnectionStateChange> get connectionStateChanges;  // broadcast
  Stream<ConnectionError> get connectionErrors;              // broadcast

  void updateAuth(PusherAuth auth);  // replaces PusherAuth used for future channel authorizations
}

// ---- Options ------------------------------------------------------------
class PusherOptions {
  const PusherOptions({
    this.auth,                   // PusherAuth? — built-in HTTP authorizer
    this.authorizer,             // PusherAuthorizer? — custom; takes precedence over auth
    this.cluster,                // String?
    this.host,                   // String? — bare hostname, no scheme/port/path
    this.wsPort = 80,
    this.wssPort = 443,
    this.encrypted = true,       // use TLS
    this.activityTimeout = 120000,          // ms
    this.pongTimeout = 30000,               // ms
    this.maxReconnectionAttempts = 6,
    this.maxReconnectGapInSeconds = 30,
  });
}

class PusherAuth {
  const PusherAuth(this.endpoint, {this.headers = const {}, this.params = const {}});
  final String endpoint;               // full URL
  final Map<String, String> headers;
  final Map<String, String> params;    // extra body params sent with socket_id/channel_name
}

typedef PusherAuthorizer = Future<PusherAuthorizationData> Function(
    String channelName, String socketId);

class PusherAuthorizationData {
  const PusherAuthorizationData({required this.auth, this.channelData, this.sharedSecret});
  factory PusherAuthorizationData.fromJson(Map<String, dynamic> json); // keys: auth, channel_data, shared_secret
  final String auth;
  final String? channelData;   // presence channels: JSON string {"user_id":..,"user_info":..}
  final String? sharedSecret;  // private-encrypted channels (base64)
}

// ---- Channels -----------------------------------------------------------
class Channel {
  final String name;
  bool get isSubscribed;              // true after pusher:subscription_succeeded, false after unsubscribe/error
  int? get subscriptionCount;         // from pusher:subscription_count (when enabled on the app)

  Future<void> bind(String eventName, void Function(PusherEvent event) onEvent); // replaces existing callback for eventName
  Future<void> unbind(String eventName);
  void bindGlobal(void Function(PusherEvent event) onEvent);  // every event on this channel
  void unbindGlobal();
  Future<void> trigger(String eventName, dynamic data);
}

class PresenceChannel extends Channel {
  Map<String, dynamic> get members;   // userId -> userInfo (unmodifiable)
  int get memberCount;
  String? get me;                     // user_id from the auth channel_data, if known
}

// ---- Models (all fields final; fromMap factories; ==/hashCode/toString) --
class PusherEvent { String? channelName; String? eventName; String? data; String? userId; }
class ConnectionStateChange { String? currentState; String? previousState; }
class ConnectionError { String? message; String? code; String? exception; }
class PusherException implements Exception { final String message; final String? code; }
```

Behavioural rules:

* `bind`/`unbind`/`bindGlobal` are **pure Dart** — native always forwards every
  event of every subscribed channel. `bind` returns a completed `Future` (kept
  `Future` for 2.x source compatibility).
* `trigger`: `eventName` gets a `client-` prefix if missing. Throws
  `PusherException(code: 'TRIGGER_ERROR')` *in Dart, before calling native*, if
  the channel is not `private-` (excluding `private-encrypted-`) or `presence-`,
  or if the channel is not yet subscribed. `data` that is a `String` is sent
  as-is; anything else is `jsonEncode`d (unencodable data also throws
  `TRIGGER_ERROR`). All three native libraries send the string as the JSON
  string value of the protocol's `data` field.
* Host validation: `PusherClient` constructor throws `ArgumentError` if
  `options.host` contains `://`, `/`, or `:` (people pass URLs — #68).
* `enableLogging` default is now `false` (was `true`).
* Calling any method after `dispose()` throws `StateError` (a second
  `dispose()` is a no-op; `appKey`/`options` stay readable).
* The `PusherClient` constructor never throws asynchronously; native call
  failures during init/connect are reported through `onConnectionError`.
* All native calls for one client are serialised in call order (init is
  awaited internally before subsequent calls are sent).

## 3. Channels & codec

* MethodChannel: `com.github.chinloyal/pusher_client` (StandardMethodCodec)
* EventChannel:  `com.github.chinloyal/pusher_client_stream`
* All arguments and payloads are `Map<String, Object?>` with String keys.
  **No JSON-encoded strings as method arguments.** (JSON strings only appear
  as Pusher event `data`, exactly as Pusher delivers it.)
* Every call and every event carries `instanceId` (String). Dart generates it
  (`"<isolate-random>-<counter>"`).

## 4. Dart → native methods

All return `null` on success unless stated. Errors: `PlatformException` with
code from §7. Unknown `instanceId` ⇒ `NO_INSTANCE` error (except `dispose`,
`disposeAll`, which are no-ops).

| method | arguments | notes |
|---|---|---|
| `disposeAll` | `{}` | Sent once per Dart isolate before the first `init` (clears native instances leaked by a hot restart). Disconnects and drops every native instance. |
| `init` | `{instanceId, appKey, enableLogging: bool, options: {...}}` | Creates the native Pusher instance. If one already exists for `instanceId`, it is disconnected and replaced. Does **not** connect. |
| `connect` | `{instanceId}` | |
| `disconnect` | `{instanceId}` | Native subscriptions are kept. |
| `dispose` | `{instanceId}` | Disconnect, unbind everything, drop instance. |
| `subscribe` | `{instanceId, channelName}` | Idempotent. Never fails for auth reasons — auth failures arrive as `pusher:subscription_error` events. |
| `unsubscribe` | `{instanceId, channelName}` | Idempotent. |
| `trigger` | `{instanceId, channelName, eventName, data: String}` | Native still validates channel type (defence in depth) and replies exactly once. |
| `getSocketId` | `{instanceId}` | Returns `String?`. (Dart normally uses the socketId carried by state-change events.) |

### 4.1 `options` map (sent by `init`)

```
{
  "cluster": String?,          // null if not set
  "host": String?,             // null if not set
  "wsPort": int, "wssPort": int,
  "useTLS": bool,              // = PusherOptions.encrypted
  "activityTimeout": int,      // ms
  "pongTimeout": int,          // ms
  "maxReconnectionAttempts": int,
  "maxReconnectGapInSeconds": int,
  "hasAuthorizer": bool        // true if auth or authorizer is configured
}
```

Host resolution (all platforms): `host != null` ⇒ use host + (`useTLS` ? wssPort : wsPort);
else `cluster != null` ⇒ cluster (`ws-<cluster>.pusher.com`); else library default.
Native always installs the Dart-delegating authorizer (`hasAuthorizer` is
informational). Without `auth`/`authorizer`, Dart answers `authorize` with
`AUTH_ERROR` "No authorizer configured. Set PusherOptions.auth or
PusherOptions.authorizer.", which surfaces as `pusher:subscription_error`.

### 4.2 Native → Dart method (on the same MethodChannel)

| method | arguments | Dart returns |
|---|---|---|
| `authorize` | `{instanceId, channelName, socketId}` | `{auth: String, channel_data: String?, shared_secret: String?}` or throws `PlatformException(code: 'AUTH_ERROR', message, details: {status: int?})` |

Native must:
* invoke on the platform main thread;
* on success, hand the values to the Pusher library's authorizer API;
* on error / timeout (**30 s**) / `notImplemented` / unknown instance in Dart,
  fail the subscription so the channel emits `pusher:subscription_error`
  (§5.3) carrying the error message and status;
* never block the platform main thread (Android: the pusher-java authorizer
  runs on the library's event thread — block *that* with a latch, post the
  Dart call to the main looper).

### 4.3 Connection states

Native normalises to upper-case strings:
`CONNECTING`, `CONNECTED`, `DISCONNECTING`, `DISCONNECTED`, `RECONNECTING`.
(pusher-java's `ALL` is never sent.) Dart's `connectionState` starts as
`DISCONNECTED`.

## 5. Native → Dart events (EventChannel)

Each event is a map with `instanceId` and `type`.

### 5.1 `connectionStateChange`
`{instanceId, type: "connectionStateChange", currentState, previousState, socketId: String?}`
— `socketId` is the current socket id after the transition (null unless connected).

### 5.2 `connectionError`
`{instanceId, type: "connectionError", message: String?, code: String?, exception: String?}`
— `code` is a string (e.g. `"4001"`) or null.

### 5.3 `event`
`{instanceId, type: "event", channelName: String, eventName: String, data: String?, userId: String?}`

Native forwards, **exactly once each**, for every subscribed channel:

| eventName | when | `data` |
|---|---|---|
| any app event / client event | received | as delivered (string) |
| `pusher:subscription_succeeded` | subscribed (once per successful subscription, incl. resubscribe after reconnect) | non-presence: `"{}"`; presence: `{"presence":{"count":N,"ids":[...],"hash":{"<id>":<info or null>}}}` |
| `pusher:subscription_error` | auth failure or server subscription error | `{"type":"AuthError","error":"<message>","status":<int or null>}` |
| `pusher:member_added` | presence member joined | `{"user_id":"<id>","user_info":<info or null>}`; `userId` = id |
| `pusher:member_removed` | presence member left | `{"user_id":"<id>"}`; `userId` = id |
| `pusher:subscription_count` | count changed (app setting) | `{"subscription_count":N}` |
| `pusher:decryption_error` | private-encrypted event failed to decrypt | `{"event":"<name>","reason":"<reason>"}` |

`user_info` must be real JSON (object/array/string/number/null), not a
`toString()` of a native collection.

## 6. Dart internals

```
lib/
  pusher_client.dart                 // exports
  src/
    pusher_client.dart               // PusherClient
    channel.dart                     // Channel, PresenceChannel
    options.dart                     // PusherOptions
    auth.dart                        // PusherAuth, PusherAuthorizer, PusherAuthorizationData, HTTP authorizer
    models.dart                      // PusherEvent, ConnectionStateChange, ConnectionError, PusherException
    platform/
      pusher_platform.dart           // abstract PusherPlatform + static instance (default MethodChannelPusherPlatform)
      method_channel_platform.dart   // MethodChannel/EventChannel implementation
    web/
      pusher_client_web.dart         // PusherClientWeb.registerWith(Registrar) -> sets PusherPlatform.instance
      ...                            // pusher-js interop (dart:js_interop + package:web)
```

`PusherPlatform` (internal, not exported):

```dart
abstract class PusherPlatform {
  static PusherPlatform instance = MethodChannelPusherPlatform();
  Stream<Map<String, Object?>> get events;            // all events, all instances (broadcast)
  set authorizeHandler(Future<Map<String, Object?>> Function(String instanceId, String channelName, String socketId)? h);
  Future<void> disposeAll();
  Future<void> init(String instanceId, String appKey, Map<String, Object?> options, bool enableLogging);
  Future<void> connect(String instanceId);
  Future<void> disconnect(String instanceId);
  Future<void> dispose(String instanceId);
  Future<void> subscribe(String instanceId, String channelName);
  Future<void> unsubscribe(String instanceId, String channelName);
  Future<void> trigger(String instanceId, String channelName, String eventName, String data);
  Future<String?> getSocketId(String instanceId);
}
```

A static registry in `PusherClient` maps `instanceId → PusherClient`; one
listener on `PusherPlatform.instance.events` dispatches to it; one
`authorizeHandler` dispatches `authorize` to the right client, which runs its
`authorizer` or the HTTP `PusherAuth`.

HTTP `PusherAuth` (uses `package:http`; the `http.Client` is injectable for tests):
* `POST endpoint`, body = `socket_id`, `channel_name` + `params`.
* If any header `content-type` (case-insensitive) contains `application/json`,
  body is JSON; otherwise `application/x-www-form-urlencoded` (Pusher's default).
* Non-2xx ⇒ `AUTH_ERROR` with `status` and a message including the response
  body (truncated to 500 chars). Invalid JSON / missing `auth` ⇒ `AUTH_ERROR`.

Presence `me`: parsed from `channel_data` (`user_id`) of the auth response.

## 7. Error codes (PlatformException.code)

`INIT_ERROR`, `NO_INSTANCE`, `INVALID_ARGUMENTS`, `SUBSCRIBE_ERROR`,
`UNSUBSCRIBE_ERROR`, `TRIGGER_ERROR`, `AUTH_ERROR`, and `PLUGIN_ERROR` for
unexpected native exceptions. Unknown method names reply `notImplemented`.

## 8. Platform specifics

### Android (`android/`)
* pusher-java-client **2.4.5** (+ gson as a compile dependency; pusher-java
  declares it runtime-only); Gradle file compatible with AGP 8.x and 9.x
  (built-in Kotlin on/off) and KGP 1.8+ — verified with Flutter 3.27.4
  (AGP 8.1/KGP 1.8), 3.35.5 (AGP 8.9/KGP 2.1), 3.44 (AGP 9.0, built-in Kotlin
  off) and 3.47.9 (AGP 9.1, built-in Kotlin on). KGP is applied only on
  AGP < 9 via `pluginManager.apply` (Flutter's Gradle plugin text-matches
  `apply plugin: 'kotlin-android'` and would otherwise treat the plugin as
  unmigrated); `namespace "com.github.chinloyal.pusher_client"`;
  compileSdk 36, minSdk 21; Java/Kotlin target 17; `consumer-rules.pro`
  keeping `com.pusher.**`, gson models, and the plugin.
* `PusherClientPlugin : FlutterPlugin, MethodCallHandler`; on detach: dispose
  all instances, clear handlers.
* Per instance: one `Pusher`; connection listener bound **once** at init
  (`pusher.connection.bind(ConnectionState.ALL, listener)`), `connect()` called
  without a listener (2.x re-bound on every connect ⇒ duplicate events, #26).
* Subscribe with the type-appropriate listener (`subscribe`, `subscribePrivate`,
  `subscribePrivateEncrypted`, `subscribePresence`) **and** `channel.bindGlobal(listener)`.
  `onSubscriptionSucceeded` ⇒ the single `pusher:subscription_succeeded` event
  (presence data built from `channel.users` with gson; do **not** emit another
  one from `onUsersInformationReceived`). `onAuthenticationFailure` ⇒
  `pusher:subscription_error`.
* Authorizer: a `ChannelAuthorizer` that posts `authorize` to the main thread
  and waits on a latch (30 s), returning the JSON string pusher-java expects
  (`{"auth":..,"channel_data":..,"shared_secret":..}`) or throwing
  `AuthorizationFailureException`.
* All sink/channel calls on the main thread; injectable main-thread executor
  and Pusher factory for unit tests. Avoid `org.json` in unit-tested code
  (stubbed in local JVM tests) — use gson / Kotlin maps.

### Darwin (`darwin/`, shared by iOS and macOS)
* `PusherSwift ~> 10.1.10` (CocoaPods) / `.upToNextMinor(from: "10.1.10")` (SwiftPM).
  iOS 13.0, macOS 10.15. (10.2.0 requires iOS 15.) SwiftPM also constrains
  `tweetnacl-swiftwrap` to 1.2.x because 1.3.0 requires iOS 15 / macOS 12.
* PusherSwift ignores `unsubscribe` for channels that have not finished
  subscribing; the plugin removes those from `connection.channels` itself and
  sends `pusher:unsubscribe` when connected.
* Layout: `darwin/pusher_client.podspec`, `darwin/pusher_client/Package.swift`,
  `darwin/pusher_client/Sources/pusher_client/*.swift`,
  `darwin/pusher_client/Sources/pusher_client/PrivacyInfo.xcprivacy`
  (bundled in both podspec `resource_bundles` and SwiftPM `resources`).
* `#if os(iOS) import Flutter #elseif os(macOS) import FlutterMacOS #endif`.
* Per instance: `Pusher` + its own `PusherDelegate` object capturing `instanceId`.
* Event forwarding: `pusher.bind(eventCallback:)` (global; drop events with no
  channelName) gives app/client events, `pusher:subscription_succeeded`
  (with server presence data) and `pusher:subscription_error`. Presence
  members via `subscribeToPresenceChannel(onMemberAdded:onMemberRemoved:)`,
  counts via `onSubscriptionCountChanged`, decryption failures via
  `PusherDelegate.failedToDecryptEvent`. Never force-unwrap.
* `Authorizer` implementation: dispatch `authorize` to main queue; on Dart error
  emit `pusher:subscription_error` ourselves and call `completionHandler(nil)`.
* Logging with `NSLog` (visible in `flutter run`), only if `enableLogging`.

### Web (`lib/src/web/`)
* pusher-js 8.x via `dart:js_interop` + `package:web`. If `window.Pusher` is
  undefined, inject `<script src="https://js.pusher.com/8.4.0/pusher-with-encryption.min.js">`
  and await load. pusher-js has no `maxReconnection*` equivalents (ignored) and
  emits no decryption-failure event. Client-event `userId` is captured by
  wrapping the channel's `emit` (pusher-js `bind_global` gets no metadata).
* `channelAuthorization.customHandler` → `authorizeHandler`.
* Same event map shapes as §5 (pusher-js names `pusher:subscription_succeeded`
  data for presence differs — convert `members` to the §5.3 shape).

## 9. Testing requirements

* **Dart unit tests** (`test/`): models; options/host validation; method call
  arguments via mocked MethodChannel; event routing incl. multiple instances;
  bind/unbind/bindGlobal; presence members lifecycle; trigger validation and
  encoding; authorizer & HTTP auth (MockClient) success/failure; dispose rules.
* **Android unit tests** (`android/src/test/kotlin`, JUnit + mockito): options
  mapping, state normalisation, event map building (presence JSON), method
  dispatch with a mocked `Pusher`, authorizer latch success/error/timeout.
  Run: `cd example/android && ./gradlew :pusher_client:testDebugUnitTest`.
* **Darwin unit tests** (`example/ios/RunnerTests`, XCTest): option mapping,
  state normalisation, event/presence payload building, method dispatch.
* **Integration tests** (`example/integration_test`) against a local
  Pusher-protocol server (soketi), signing auth locally in Dart; public,
  private, presence, client events, encrypted (if feasible).
