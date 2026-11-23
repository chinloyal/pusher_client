# Integration tests

End-to-end tests that run the real plugin (native Android / iOS / macOS code)
against a local [soketi](https://docs.soketi.app) server, which speaks the
Pusher protocol. Channel authorization is signed locally in Dart and events are
triggered through the signed Pusher REST API, so no Pusher account is needed.

## Quick start

```sh
cd example
integration_test/run.sh macos                 # or an iOS simulator id / emulator-5554
```

`run.sh` locates Node 18, starts soketi, waits until it is healthy, runs
`flutter test integration_test -d <device>` with the right `--dart-define`s and
always stops soketi again (trap on exit).

* **Node 18 is required** for soketi 1.6.1 (uWebSockets.js ships no binary for
  Node 20+). Set `NODE18=/path/to/node`, or install it with `nvm install 18`
  (the script looks in `~/.nvm/versions/node/v18.*`).
* No Node 18? `USE_DOCKER=1 integration_test/run.sh macos` runs
  `quay.io/soketi/soketi:1.6-16-alpine` instead.
* The Android emulator reaches your computer as `10.0.2.2`; `run.sh` picks that
  automatically for `emulator-*` devices. Override with `PUSHER_HOST=...`.
  Debug builds allow cleartext traffic (see `android/app/src/debug`).

## Dart defines

| Define | Default | Meaning |
|---|---|---|
| `PUSHER_HOST` | `127.0.0.1` | Host the app uses to reach soketi |
| `PUSHER_PORT` | `6001` | soketi port |
| `PUSHER_KEY` | `app-key` | App key |
| `PUSHER_SECRET` | `app-secret` | App secret (used to sign auth and REST calls) |
| `PUSHER_APP_ID` | `app-id` | App id (REST API path) |

## Manual run

```sh
SOKETI_DEFAULT_APP_ID=app-id SOKETI_DEFAULT_APP_KEY=app-key \
SOKETI_DEFAULT_APP_SECRET=app-secret SOKETI_DEFAULT_APP_ENABLE_CLIENT_MESSAGES=true \
  node18 node_modules/@soketi/soketi/bin/server.js start   # curl http://127.0.0.1:6001/ -> OK
flutter test integration_test -d macos
```

## Web

`dart:io` (the in-app auth endpoint and REST helper) is not available in the
browser, so these tests do not run on web. Web is covered by the unit tests
and the demo app.

## What is covered

`pusher_client_test.dart`: connect / disconnect / reconnect (callback and
stream), public channels (REST-triggered events, `bind` replacement, `unbind`,
`bindGlobal`, unsubscribe), private channels via `authorizer` and via
`PusherAuth` (form and JSON bodies, custom headers and params), auth failure
(403) followed by `updateAuth` + re-subscribe, presence (members, `me`,
`member_added`, `member_removed`), client events (private and presence, sender
`userId` on Android / iOS / macOS), trigger validation errors,
private-encrypted channels (secretbox via `package:pinenacl`), `dispose`
semantics and isolation between several clients.

`support.dart` holds the helpers (auth signing, REST trigger, in-app
`HttpServer` auth endpoint, event recorder).

## Known server quirk

soketi 1.6.1 sends `pusher_internal:subscription_succeeded` for public and
private channels *without* the `data` field that Pusher always includes
(`"{}"`). The plugin compensates on iOS / macOS (PusherSwift 10.1.10 would
otherwise drop the message), but pusher-java throws an uncaught NPE (app crash)
on **private-encrypted** channels with such a server (upstream bug). `run.sh`
therefore patches its own installed copy of soketi to send `data:"{}"` so the
whole suite runs on Android too. Set `SOKETI_STOCK=1` (or use `USE_DOCKER=1`)
to run against unpatched soketi — on iOS / macOS everything should still pass;
on Android skip the encrypted test.
