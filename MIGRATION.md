# Migrating from 2.x to 3.0.0

3.0.0 is a rewrite of the plugin internals with a few source-breaking API changes. Most apps need only the
small edits below.

## Checklist

1. Raise your minimums: Dart SDK `^3.6.0`, Flutter `>=3.27.0`, Android `minSdk 21`, iOS 13.0, macOS 10.15.
2. Stop relying on `PusherClient` being a singleton; keep your own reference and call `dispose()`.
3. Turn logging on explicitly if you relied on the old default.
4. Review your authorization setup (body encoding, `PusherAuth` signature).
5. Remove old workarounds (ProGuard rule, Podfile edits).

## Breaking changes

### The singleton is gone

In 2.x `PusherClient(...)` always returned the same instance, so the first options (and the first auth token)
were used forever. In 3.0.0 every `PusherClient` is independent, with its own connection. Creating one twice gives
you two connections, so keep a reference and `dispose()` it when done.

```dart
// 2.x
final a = PusherClient(key, options);
final b = PusherClient(key, otherOptions); // same object as a, otherOptions ignored

// 3.0.0
final a = PusherClient(key, options);
final b = PusherClient(otherKey, otherOptions); // a different connection
// ... later
await a.dispose();
await b.dispose();
```

Multiple instances (several apps / clusters) now work. After `dispose()` any method call throws a `StateError`.
To change the auth token without recreating the client use `updateAuth`:

```dart
pusher.updateAuth(PusherAuth(url, headers: {'Authorization': 'Bearer $newToken'}));
```

### `enableLogging` defaults to `false`

It used to default to `true`.

```dart
// 2.x: logging on unless disabled
PusherClient(key, options, enableLogging: false);

// 3.0.0: logging off unless enabled
PusherClient(key, options, enableLogging: true);
```

### Authorization happens in Dart

Channel authorization is now performed by the plugin's Dart code on every platform instead of by each native
library, so behaviour is identical everywhere.

- The request body is `application/x-www-form-urlencoded` (`socket_id=...&channel_name=...`), the format Pusher
  servers and Laravel expect. In 2.x the default `PusherAuth` headers forced `Content-Type: application/json`.
  If your endpoint needs JSON, set the header yourself; the body is then sent as JSON.

```dart
// 2.x
PusherAuth(url, headers: {'Authorization': 'Bearer $token'}); // sent as JSON by default

// 3.0.0 - form-urlencoded
PusherAuth(url, headers: {'Authorization': 'Bearer $token'});
// 3.0.0 - JSON, as before
PusherAuth(url, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});
```

- Failures no longer disappear silently: the channel receives `pusher:subscription_error` (see below).
- A new `PusherOptions.authorizer` callback lets you authorize with your own code (see the README).

### `PusherAuth` constructor

```dart
const PusherAuth(String endpoint, {Map<String, String> headers = const {}, Map<String, String> params = const {}})
```

`headers` now defaults to an empty map (there are no forced default headers any more) and the new `params` are
extra body fields sent along with `socket_id` and `channel_name`. Use a full URL for `endpoint`.

### `PusherEvent` callback parameter is non-nullable

```dart
// 2.x
channel.bind('evt', (PusherEvent? event) => print(event?.data));

// 3.0.0
channel.bind('evt', (PusherEvent event) => print(event.data));
```

The fields of `PusherEvent` (`channelName`, `eventName`, `data`, `userId`) are still nullable.

### Connection states are upper-case on all platforms

`ConnectionStateChange.currentState` / `previousState` are always `CONNECTING`, `CONNECTED`, `DISCONNECTING`,
`DISCONNECTED` or `RECONNECTING`. Compare against these (2.x delivered different casing per platform).

### `pusher:subscription_error` is delivered

Failed subscriptions (most commonly failed authorization) now emit `pusher:subscription_error` to bindings on the
channel, with `data` like `{"type":"AuthError","error":"...","status":403}`. Re-call `pusher.subscribe(name)` to
retry. Callbacks bound with `bindGlobal` also see this event.

### `host` wins over `cluster`

If both are set, `host` is used and `cluster` is ignored (previously the outcome differed by platform, and iOS
could end up on the Pusher cloud with a self-hosted setup). `host` must be a bare hostname; a URL or `host:port`
throws an `ArgumentError` from the `PusherClient` constructor.

```dart
// 2.x (cluster was sometimes needed as a workaround)
PusherOptions(host: 'example.com', cluster: 'mt1', wsPort: 6001, encrypted: false)

// 3.0.0
PusherOptions(host: 'example.com', wsPort: 6001, encrypted: false)
```

### Trigger validation throws `PusherException`

`channel.trigger(...)` now validates in Dart and throws `PusherException(code: 'TRIGGER_ERROR')` when the channel is
not `private-` / `presence-` or is not subscribed yet. Wrap calls in `try`/`catch` if you may call it early.
Non-string `data` is JSON-encoded; strings are sent as-is.

### Minimum versions

| | 2.x | 3.0.0 |
|---|---|---|
| Dart SDK | `>=2.12 <3.0` | `^3.6.0` |
| Flutter | `<2.0.0` constraint | `>=3.27.0` |
| Android minSdk | 16 | 21 |
| iOS | 9.0 | 13.0 |

### iOS dependency

The plugin now depends on `PusherSwift` instead of the deprecated `PusherSwiftWithEncryption` (encrypted channels
are supported by `PusherSwift`). Remove any Podfile workarounds you added for 2.x, such as `post_install` hooks
that edit `IPHONEOS_DEPLOYMENT_TARGET`, `EXCLUDED_ARCHS` / arm64 simulator exclusions, or
`BUILD_LIBRARY_FOR_DISTRIBUTION`, and the `platform :ios, '9.0'` edit. Run `pod repo update && pod install` (or
`flutter clean`) once.

### Android ProGuard / R8

Remove `-keep class com.github.chinloyal.pusher_client.** { *; }` from your `proguard-rules.pro`; the plugin ships
consumer rules.

## Unchanged

- `bind` still keeps **one callback per event name** per channel; binding again replaces it (use `bindGlobal` or
  your own fan-out for several listeners). `bind` / `unbind` still return a `Future`.
- `pusher.getSocketId()`, `onConnectionStateChange`, `onConnectionError`, `subscribe`, `unsubscribe`, `connect`,
  `disconnect` keep their names and shapes.

## New in 3.0.0

Web and macOS support, multiple clients, `dispose()`, `updateAuth`, custom `authorizer`, `PusherAuth.params`,
`connectionState`, `socketId`, `channel(name)`, `channels`, `Channel.isSubscribed`,
`Channel.subscriptionCount`, `bindGlobal` / `unbindGlobal`, `PresenceChannel.members` / `memberCount` / `me`,
`connectionStateChanges` and `connectionErrors` streams. See the [CHANGELOG](CHANGELOG.md).
