# Pusher Channels Flutter Client

[![pub version](https://img.shields.io/pub/v/pusher_client.svg?logo=dart)](https://pub.dev/packages/pusher_client)
[![CI](https://github.com/chinloyal/pusher_client/actions/workflows/ci.yml/badge.svg)](https://github.com/chinloyal/pusher_client/actions/workflows/ci.yml)
[![GitHub license](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/chinloyal/pusher_client/master/LICENSE)
![Languages](https://img.shields.io/badge/languages-dart%20%7C%20kotlin%20%7C%20swift-blueviolet.svg)
[![Twitter](https://img.shields.io/badge/twitter-@chinloyal-blue.svg?style=flat&logo=twitter)](https://twitter.com/chinloyal)

A Pusher Channels client plugin for Flutter targeting Android, iOS, macOS and web. It wraps
[pusher-websocket-java](https://github.com/pusher/pusher-websocket-java) 2.4.5,
[pusher-websocket-swift](https://github.com/pusher/pusher-websocket-swift) 10.1.x and, on the web,
[pusher-js](https://github.com/pusher/pusher-js) 8.4.0.

For tutorials and more in-depth information about Pusher Channels, visit the [official docs](https://pusher.com/docs/channels).

This client works with the official Pusher Channels service and with Pusher-protocol compatible self-hosted
servers such as [soketi](https://soketi.app), [Laravel Reverb](https://reverb.laravel.com) and
[laravel-websockets](https://github.com/beyondcode/laravel-websockets).

> Upgrading from 2.x? Read [MIGRATION.md](MIGRATION.md).

## Supported Platforms & Deployment Targets

| Platform | Minimum |
|---|---|
| Android | API 21 |
| iOS | 13.0 |
| macOS | 10.15 |
| Web | any browser supported by pusher-js 8 |

Requires Dart `^3.6.0` and Flutter `>=3.27.0`.

## Table of Contents

- [Installation](#installation)
- [Platform setup](#platform-setup)
- [API overview](#api-overview)
- [The PusherClient constructor](#the-pusherclient-constructor)
- [PusherOptions](#pusheroptions)
- [Connecting, disconnecting and disposing](#connecting-disconnecting-and-disposing)
- [Authorization](#authorization)
- [Subscribing to channels](#subscribing-to-channels)
- [Binding to events](#binding-to-events)
- [Triggering client events](#triggering-client-events)
- [Connection state and errors](#connection-state-and-errors)
- [Socket ID](#socket-id)
- [Self-hosted servers](#self-hosted-servers)
- [Logging](#logging)
- [Platform limitations](#platform-limitations)
- [Troubleshooting](#troubleshooting)
- [Migrating from 2.x](#migrating-from-2x)

## Installation

```yaml
dependencies:
  pusher_client: ^3.0.0
```

```dart
import 'package:pusher_client/pusher_client.dart';
```

## Platform setup

### iOS

iOS 13.0 or newer is required, which is already the Flutter default, so no Podfile edit is needed.
Both CocoaPods and Swift Package Manager are supported.

App Transport Security only matters if you connect with plain `ws://` / `http://` to a host that is not
`localhost`. In that case add an exception to `ios/Runner/Info.plist`, preferably for your domain only:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>example.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```

(`NSAllowsArbitraryLoads` also works but is not recommended for production apps.)

### macOS

macOS 10.15 or newer is required. Sandboxed macOS apps need the outgoing network entitlement in both
`macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

### Android

Android API 21 or newer. Make sure `android/app/src/main/AndroidManifest.xml` declares the internet permission
(Flutter adds it to debug builds only):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

No ProGuard / R8 rules are needed: the plugin ships its own consumer rules.

### Web

pusher-js is loaded automatically from the Pusher CDN (`https://js.pusher.com/8.4.0/`) the first time a client is
created. If you prefer to load it yourself (for example to self-host it or to pin another 8.x version), add it to
`web/index.html` **before** the Flutter bootstrap script; the plugin skips loading when `window.Pusher` already exists:

```html
<script src="https://js.pusher.com/8.4.0/pusher-with-encryption.min.js"></script>
```

Use the `pusher-with-encryption` build if you want to use private-encrypted channels.

If your site sets a Content-Security-Policy, allow `https://js.pusher.com` in `script-src` (not needed if you
self-host the script) and the websocket endpoint in `connect-src`, for example
`wss://ws-mt1.pusher.com wss://sockjs-mt1.pusher.com https://sockjs-mt1.pusher.com`, or your own server's host.

## API overview

```dart
final pusher = PusherClient(
  'YOUR_APP_KEY',
  PusherOptions(
    cluster: 'mt1',
    auth: PusherAuth(
      'https://example.com/broadcasting/auth',
      headers: {'Authorization': 'Bearer $token'},
    ),
  ),
  autoConnect: false,
);

// connect at a later time than at instantiation.
await pusher.connect();

pusher.onConnectionStateChange((state) {
  print('previous: ${state.previousState}, current: ${state.currentState}');
});

pusher.onConnectionError((error) {
  print('error: ${error.message}');
});

// Subscribe to a private channel
final channel = pusher.subscribe('private-orders');

// Listen for "order-status-updated" events on the "private-orders" channel
channel.bind('order-status-updated', (PusherEvent event) {
  print(event.data);
});

// Unsubscribe from the channel
await pusher.unsubscribe('private-orders');

// Disconnect (subscriptions are kept, connect() resumes them)
await pusher.disconnect();

// Release the native resources when you are done with the client
await pusher.dispose();
```

## The PusherClient constructor

The constructor takes your app key (from the *App Keys* section of the Channels dashboard) and a
`PusherOptions`:

```dart
final pusher = PusherClient('YOUR_APP_KEY', const PusherOptions(cluster: 'mt1'));
```

There is **no singleton**: every `PusherClient` is an independent connection with its own native instance. Keep a
reference to it (for example in a service or a provider) and call `dispose()` when you no longer need it. You can
create several clients, for example to talk to two different apps or clusters at once:

```dart
final eu = PusherClient('KEY_A', const PusherOptions(cluster: 'eu'));
final us = PusherClient('KEY_B', const PusherOptions(cluster: 'us2'));
```

Optional named parameters:

```dart
final pusher = PusherClient(
  'YOUR_APP_KEY',
  options,
  enableLogging: true, // default false
  autoConnect: false,  // default true; call connect() yourself
);
```

The constructor never fails asynchronously: if a native call fails during initialisation or connect it is reported
through `onConnectionError` / `connectionErrors`. It throws an `ArgumentError` synchronously when
`PusherOptions.host` is not a bare hostname (see below).

## PusherOptions

| Option | Type | Default | Description |
|---|---|---|---|
| `auth` | `PusherAuth?` | `null` | Built-in HTTP authorizer used for private, private-encrypted and presence channels. Ignored when `authorizer` is set. |
| `authorizer` | `PusherAuthorizer?` | `null` | Custom authorization callback. Takes precedence over `auth`. |
| `cluster` | `String?` | `null` | The Channels cluster, e.g. `mt1`, `eu`, `us2`. Ignored when `host` is set. |
| `host` | `String?` | `null` | Host for self-hosted servers. Must be a **bare hostname**: no `https://`, no port, no path (`example.com`, not `https://example.com:6001`). Wins over `cluster`. |
| `wsPort` | `int` | `80` | Port used for non-TLS connections (when `encrypted: false`). |
| `wssPort` | `int` | `443` | Port used for TLS connections (when `encrypted: true`). |
| `encrypted` | `bool` | `true` | Use TLS. |
| `activityTimeout` | `int` | `120000` | Milliseconds of inactivity before a ping is sent. |
| `pongTimeout` | `int` | `30000` | Milliseconds to wait for the pong before the connection is considered broken. |
| `maxReconnectionAttempts` | `int` | `6` | Number of reconnect attempts after the socket failed. Ignored on web. |
| `maxReconnectGapInSeconds` | `int` | `30` | Maximum delay between two reconnect attempts (the delay doubles from 1 second). Ignored on web. |

Host resolution: if `host` is set the client connects to `host` on `wssPort` (when `encrypted`) or `wsPort`;
otherwise if `cluster` is set it connects to `ws-<cluster>.pusher.com`; otherwise the library default is used. If
you use `host`, do not rely on `cluster` for anything.

## Connecting, disconnecting and disposing

- `connect()` opens the connection. It is called for you unless you pass `autoConnect: false`.
- `disconnect()` closes the connection but keeps your subscriptions and bindings; `connect()` resumes them.
- `dispose()` disconnects and releases the native instance. A disposed client must not be used any more: calling
  its methods throws a `StateError`.

## Authorization

Private, private-encrypted and presence channels need an authorization signature from your server. All
authorization is performed in Dart (the same way on every platform), either by the built-in HTTP authorizer
(`PusherAuth`) or by your own `authorizer` callback.

### `PusherAuth`

```dart
final options = PusherOptions(
  cluster: 'mt1',
  auth: PusherAuth(
    // Use the full URL, including the scheme.
    'https://example.com/broadcasting/auth',
    headers: {'Authorization': 'Bearer $token'},
    params: {'tenant': 'acme'}, // extra body fields sent with socket_id / channel_name
  ),
);
```

The plugin sends `POST <endpoint>` with `socket_id` and `channel_name` (plus your `params`). The body is
`application/x-www-form-urlencoded`, which is what Pusher's server libraries expect, unless you set a
`Content-Type` header containing `application/json`, in which case the body is JSON:

```dart
PusherAuth(
  'https://example.com/broadcasting/auth',
  headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
);
```

The endpoint must answer with a 2xx and a JSON object containing `auth` (and `channel_data` for presence channels,
`shared_secret` for private-encrypted channels).

### Refreshing tokens: `updateAuth`

When your bearer token changes (login, refresh) call `updateAuth`. It applies to every authorization from then on:

```dart
pusher.updateAuth(PusherAuth(
  'https://example.com/broadcasting/auth',
  headers: {'Authorization': 'Bearer $newToken'},
));
```

It has no effect if you configured an `authorizer`.

### Custom `authorizer`

For full control (your own API client, token refresh logic, Laravel Sanctum cookies, signing locally in tests...)
provide a `PusherAuthorizer`. It is called with the channel name and the socket id and returns a
`PusherAuthorizationData`; throw to fail the subscription.

```dart
final options = PusherOptions(
  cluster: 'mt1',
  authorizer: (String channelName, String socketId) async {
    final response = await myApi.post('/broadcasting/auth', data: {
      'socket_id': socketId,
      'channel_name': channelName,
    }); // e.g. a Dio / http client that already holds your Sanctum token
    return PusherAuthorizationData.fromJson(
      response.data as Map<String, dynamic>, // keys: auth, channel_data, shared_secret
    );
  },
);
```

### Authorization failures

If authorization fails (non-2xx response, unreachable server, invalid JSON, your authorizer throws, or neither
`auth` nor `authorizer` is configured) the channel receives a `pusher:subscription_error` event. Its `data` is a
JSON string such as `{"type":"AuthError","error":"<message>","status":403}`:

```dart
final channel = pusher.subscribe('private-orders');
channel.bind('pusher:subscription_error', (event) {
  print('could not subscribe: ${event.data}');
});
```

To retry (for example after refreshing the token with `updateAuth`), call `pusher.subscribe(name)` again. A
channel whose subscription failed is subscribed again; a healthy channel is returned as-is.

## Subscribing to channels

`subscribe` returns immediately with a `Channel` (a `PresenceChannel` for `presence-` names). Subscribing to a name
that is already subscribed returns the same object. `channel.isSubscribed` becomes `true` once the server confirms
the subscription (`pusher:subscription_succeeded`). Use `pusher.channel(name)` to look a channel up and
`pusher.channels` for all of them.

### Public channels

```dart
final channel = pusher.subscribe('my-channel');
channel.bind('my-event', (event) => print(event.data));
```

### Private channels

Need `auth` or `authorizer`.

```dart
final channel = pusher.subscribe('private-orders');
```

### Private encrypted channels

Need `auth` or `authorizer` (the response must carry `shared_secret`). Event data is decrypted for you.

```dart
final channel = pusher.subscribe('private-encrypted-orders');
```

### Presence channels

Need `auth` or `authorizer`; the authorization response must include `channel_data`.

```dart
final presence = pusher.subscribe('presence-room') as PresenceChannel;

presence.bind('pusher:subscription_succeeded', (_) {
  print('members: ${presence.memberCount}, me: ${presence.me}');
  presence.members.forEach((userId, userInfo) => print('$userId -> $userInfo'));
});
presence.bind('pusher:member_added', (event) => print('joined: ${event.userId}'));
presence.bind('pusher:member_removed', (event) => print('left: ${event.userId}'));
```

- `members` is an unmodifiable `Map<String, dynamic>` of user id to user info.
- `memberCount` is the number of members.
- `me` is the current user's id, taken from the authorization `channel_data` (or `null` if not known yet).

`channel.subscriptionCount` holds the latest `pusher:subscription_count` value, if the feature is enabled for your
Channels app.

## Binding to events

```dart
channel.bind('order-status-updated', (PusherEvent event) {
  print(event.channelName); // String?
  print(event.eventName);   // String?
  print(event.data);        // String? - the raw payload, usually JSON
  print(event.userId);      // String? - set on presence member events
});
```

Decode `data` yourself: `jsonDecode(event.data!)`.

- `bind` registers **one** callback per event name per channel; binding the same event name again replaces the
  previous callback.
- `bindGlobal(callback)` is called for **every** event on the channel (including `pusher:` events). It also keeps
  a single callback; call `unbindGlobal()` to remove it.
- `unbind(eventName)` removes the callback of that event.

```dart
channel.bindGlobal((event) => print('${event.eventName}: ${event.data}'));
channel.unbindGlobal();
await channel.unbind('order-status-updated');
```

Bindings can be added before the channel is subscribed, and survive reconnects.

Laravel note: events broadcast by class use the namespaced class name as the event name unless you override
`broadcastAs()`. With `broadcastAs()` returning `order.shipped`, bind `order.shipped` (not `.order.shipped`).

## Triggering client events

```dart
await channel.trigger('typing', {'user': 'ann'}); // sent as "client-typing"
```

Rules:

- Only on `private-` and `presence-` channels. Public and `private-encrypted-` channels cannot trigger client
  events.
- Only after the channel is subscribed (`channel.isSubscribed`, or after `pusher:subscription_succeeded`).
- Client events must be enabled for your Channels app (and on self-hosted servers).
- The event name gets a `client-` prefix if it does not have one.
- A `String` is sent as-is; any other value (`Map`, `List`, number...) is JSON-encoded.
- Breaking any of these rules throws a `PusherException` with `code == 'TRIGGER_ERROR'`.

## Connection state and errors

```dart
pusher.onConnectionStateChange((state) {
  print('${state.previousState} -> ${state.currentState}');
});
pusher.onConnectionError((error) {
  print('${error.code}: ${error.message}');
});
```

Or with streams (broadcast streams, any number of listeners):

```dart
final sub = pusher.connectionStateChanges.listen((s) => print(s.currentState));
pusher.connectionErrors.listen((e) => print(e.message));
```

State strings are upper-case on every platform: `CONNECTING`, `CONNECTED`, `DISCONNECTING`, `DISCONNECTED`,
`RECONNECTING`. `pusher.connectionState` returns the current one (`DISCONNECTED` before connecting).

`onConnectionStateChange` / `onConnectionError` keep one callback each (setting a new one replaces the old);
use the streams if you need several listeners. `ConnectionError` has `message`, `code` (for example `"4001"`) and
`exception`. Failed native calls are also reported here.

## Socket ID

```dart
final socketId = pusher.socketId; // or pusher.getSocketId(); null unless connected
```

Send it to your server (for example in the `X-Socket-ID` header) to exclude the sender from a broadcast.

## Self-hosted servers

Point the client at your server with `host` (bare hostname), the port, and `encrypted`. Do not set `cluster`.

```dart
// soketi / Laravel Reverb / laravel-websockets without TLS
final pusher = PusherClient(
  'app-key',
  PusherOptions(
    host: 'example.com',
    wsPort: 6001,
    encrypted: false,
    auth: PusherAuth('http://example.com/broadcasting/auth',
        headers: {'Authorization': 'Bearer $token'}),
  ),
);
```

With TLS, use `encrypted: true` (the default) and `wssPort`, e.g. `PusherOptions(host: 'ws.example.com', wssPort: 443)`.
Laravel Reverb listens on port 8080 by default; soketi and laravel-websockets on 6001.

When you run the server on your development machine and the app on the **Android emulator**, the host machine is
reachable as `10.0.2.2` (use `host: '10.0.2.2'`); on the iOS simulator and on macOS use `localhost`. On a real
device use your machine's LAN IP or a real domain.

Self-signed certificates: browsers, iOS and Android reject them. Use plain `ws://` in development or install a
trusted development CA.

Plain `http://` auth endpoints on Android: Android 9+ blocks cleartext HTTP by default, which also applies to the
plugin's Dart-side authorization request. For local development allow it, e.g. in
`android/app/src/debug/AndroidManifest.xml`:

```xml
<application android:usesCleartextTraffic="true" />
```

Servers that omit `data` from subscription confirmations: the Pusher protocol always sends
`"data"` with `pusher_internal:subscription_succeeded`, but some compatible servers (for example soketi 1.x and
laravel-websockets) leave it out for public and private channels.

- iOS / macOS: handled by the plugin. (pusher-websocket-swift would otherwise never report
  `pusher:subscription_succeeded`, which is why such setups "worked on Android but not on iOS" in 2.x.)
- Android: public, private and presence channels work. **Private-encrypted** channels crash inside
  pusher-websocket-java when such a server confirms the subscription (an upstream library bug), so use encrypted
  channels only with servers that include `data` (such as Pusher Channels).

## Logging

`enableLogging` is `false` by default. Pass `enableLogging: true` to log plugin and native activity (visible in
`flutter run` output, logcat and the browser console).

## Platform limitations

- **Web ignores `maxReconnectionAttempts` and `maxReconnectGapInSeconds`**; pusher-js manages reconnection itself.
- **`pusher:decryption_error` is not emitted on web.**
- **No delivery in the background.** Channels is a websocket service: when the OS suspends or kills your app
  (backgrounded on iOS, device locked, app terminated) the socket is closed and events are not delivered. Use push
  notifications (FCM / APNs) to wake the app and then reconnect.
- Client events can only be sent on private and presence channels (a Pusher protocol rule).

## Troubleshooting

- **`MissingPluginException(No implementation found for method init ...)`** - the native side of the plugin was
  not part of the running app, for example because you added the plugin and only hot restarted. Stop the app and do
  a full rebuild (`flutter run` again; if it persists, `flutter clean`).
- **"App key ... not in this cluster. Did you forget to specify the cluster?" (error code 4001)** - the client is
  talking to Pusher Channels cloud with the wrong cluster, or to a self-hosted server it did not intend to. Set the
  correct `cluster`, or set `host` (and `wsPort`/`wssPort`/`encrypted`) for self-hosted servers.
- **Failing to connect to `localhost` / `::1` port 80** - neither `host` nor `cluster` was set.
- **`ArgumentError` for `options.host`** - pass only the hostname (`example.com`), not a URL.
- **Private/presence subscription fails** - bind `pusher:subscription_error` and read `event.data`; it contains the
  server's status and message. Check the auth URL is complete (with `https://`), that it returns JSON with `auth`,
  and that your bearer token is current (`updateAuth`).
- **Events are not received** - the event name must match exactly what the server sends. With Laravel, set
  `broadcastAs()` or bind the full namespaced class name.
- **Android: `CertPathValidatorException: Trust anchor for certification path not found`** - the server (or auth
  endpoint) presents a self-signed certificate or an incomplete chain. Fix the certificate chain (serve the
  intermediate certificates); Dart's `HttpOverrides` does not affect the Android websocket.
- **Android release build crashes** - make sure you are on 3.x; the consumer ProGuard rules are included.
- **Events stop when the app is in the background** - see [Platform limitations](#platform-limitations).

## Migrating from 2.x

3.0.0 has breaking changes (no singleton, logging off by default, authorization done in Dart, new minimum
platform versions...). See [MIGRATION.md](MIGRATION.md).
