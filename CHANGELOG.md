## 3.0.0 - November 22, 2026

Complete rewrite of the platform layer. See [MIGRATION.md](MIGRATION.md) for upgrade instructions.

### Breaking

* `PusherClient` is no longer a singleton: every instance is independent and owns its own native connection. Call `dispose()` when done.
* `enableLogging` now defaults to `false`.
* Channel authorization is performed in Dart on every platform. The body is `application/x-www-form-urlencoded` unless a `Content-Type: application/json` header is set (the 2.x default headers forced JSON).
* `PusherAuth` constructor is now `PusherAuth(endpoint, {headers = const {}, params = const {}})`.
* The `PusherEvent` callback parameter is non-nullable.
* Connection states are normalised to upper-case strings (`CONNECTING`, `CONNECTED`, `DISCONNECTING`, `DISCONNECTED`, `RECONNECTING`) on all platforms.
* Failed subscriptions are delivered as `pusher:subscription_error` events.
* `PusherOptions.host` takes precedence over `cluster` and must be a bare hostname (`ArgumentError` otherwise).
* `Channel.trigger` validation errors (wrong channel type, not subscribed yet) are thrown as `PusherException` with code `TRIGGER_ERROR`.
* Minimum versions: Dart `^3.6.0`, Flutter `>=3.27.0`, Android minSdk 21, iOS 13.0, macOS 10.15.

### Added

* Web support (pusher-js 8.4.0, loaded from the Pusher CDN unless already on the page) (#17, #40).
* macOS support (#40).
* Multiple independent `PusherClient` instances, e.g. several apps or clusters at once (#20, #73).
* `PusherClient.dispose()`, `updateAuth(PusherAuth)` for refreshed tokens, and `PusherOptions.authorizer` for custom authorization (#10, #25, #47).
* `PusherAuth.params` for extra authorization body fields.
* `PusherClient.connectionState`, `socketId`, `channel(name)`, `channels`, and the `connectionStateChanges` / `connectionErrors` streams (#23).
* `Channel.isSubscribed`, `Channel.subscriptionCount`, `bindGlobal` / `unbindGlobal` (#49, #52).
* `PresenceChannel.members`, `memberCount` and `me` (#2, #52).
* Swift Package Manager support for iOS and macOS, alongside CocoaPods.
* iOS/macOS privacy manifest (`PrivacyInfo.xcprivacy`) (#81).
* Unit tests for Dart, Android and iOS, web tests, and integration tests against a local soketi server; GitHub Actions CI and automated publishing to pub.dev.

### Fixed

* Android build errors with current Gradle / Kotlin / AGP: namespace, Kotlin version, `jcenter()` removed (#69, #79, #80).
* iOS build failures: PusherSwift 10 replaces the deprecated `PusherSwiftWithEncryption` (including the arm64 simulator libsodium errors, Xcode 13+ and the old iOS 8/9 deployment target) (#27, #32, #36, #46, #50, #51, #67, #79).
* iOS Reachability clash with other plugins, now that PusherSwift no longer depends on it (#6).
* Stale auth headers / token after logging in again; `PusherAuth` and options could never change (#10, #25, #47).
* Duplicate `pusher:subscription_succeeded` events on Android (#26).
* Binding to events cancelling connection state callbacks, and events not reaching Dart (#7, #34).
* Android `Reply already submitted` crash in `trigger` (#43).
* iOS crash (force-unwrap) when binding/unbinding after unsubscribing (#38).
* `pusher:member_added` / `pusher:member_removed` missing on iOS, and presence member data not valid JSON on Android (#2).
* Android release (R8) crashes: consumer ProGuard rules are now shipped and pusher-websocket-java is upgraded (#14, #29).
* Android NPE when the auth endpoint returns an unparseable response; it is now reported as `pusher:subscription_error` (#78).
* iOS private/presence authorization failing because of the request body format (#28).
* iOS ignoring a custom `host` in favour of the Pusher cloud when `cluster` was also set (#33).
* Trigger on a channel that is not yet subscribed now fails with a clear `PusherException` instead of a native error (#49).

### Changed

* pusher-websocket-java 2.2.5 -> 2.4.5.
* iOS: `PusherSwiftWithEncryption` 8.0 -> `PusherSwift` 10.1.x (iOS 13.0, macOS 10.15).
* Web: pusher-js 8.4.0.
* Android: Gradle/AGP 8 and 9 compatible build, compileSdk 36, minSdk 21, Java/Kotlin 17.
* Dart SDK `^3.6.0`, Flutter `>=3.27.0`; dependencies `http`, `meta`, `web`.
* No ProGuard rule is needed in apps any more (consumer rules are shipped).

### Removed

* The `PusherClient` singleton.
* The native authorization code paths (replaced by Dart authorization).
* The `-keep class com.github.chinloyal.pusher_client.**` ProGuard requirement and the `PusherSwiftWithEncryption` pod dependency.

## 2.0.0 - August 31, 2021

* Upgraded to null safety [@nizwar](https://github.com/nizwar)

## 1.1.3 - January 24, 2021
* BUGFIX: Binding to channel events cancels calls to onConnectionStateChange
* Added a Stream Handler contract to allow multiple classes to listen to the same event channel

## 1.1.2 - January 20, 2021
* PATCH: Removed log4j dependency for android

## 1.1.1 - January 19, 2021
* BUGFIX: ConnectionEventListener null safety issue for Android (fixed by [@spiritinlife](https://github.com/spiritinlife))

## 1.1.0 - November 20, 2020
* MINOR: Removed json_serializable and build_runner dependencies, this prevents conflict with projects that have to use those libraries at a specific version.

## 1.0.2 - November 17, 2020
* BUGFIX: Fixes issue #1, Double backslashes in the bind event breaks the JSON encoding. (This issue was only on android, iOS worked fine.)

## 1.0.1 - November 7, 2020

* BUGFIX: Fixed not being able to bind to multiple types of channels at once.

## 1.0.0 - October 26, 2020

* This is a complete Pusher Channels client library for flutter that fully supports Android and iOS with all the necessary and newest features such as having private encrypted channels. Triggering client event also works on both Android and iOS
