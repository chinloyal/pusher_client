# pusher_client example

A demo app for the `pusher_client` plugin. It runs on Android, iOS, macOS and web and is configured with
`--dart-define` values (nothing secret is stored in the source).

| Define | Meaning | Example |
|---|---|---|
| `PUSHER_KEY` | Pusher app key | `app-key` |
| `PUSHER_CLUSTER` | Channels cluster (ignored when `PUSHER_HOST` is set) | `mt1` |
| `PUSHER_HOST` | Bare hostname of a self-hosted server | `localhost` |
| `PUSHER_PORT` | Port of the self-hosted server | `6001` |
| `PUSHER_TLS` | `true` / `false`: use TLS | `false` |
| `AUTH_ENDPOINT` | Full URL of your channel authorization endpoint | `http://localhost:3000/pusher/auth` |

## Against Pusher Channels

```sh
cd example
flutter run \
  --dart-define=PUSHER_KEY=your_key \
  --dart-define=PUSHER_CLUSTER=mt1 \
  --dart-define=AUTH_ENDPOINT=https://your-backend.example.com/broadcasting/auth
```

`AUTH_ENDPOINT` is only needed for private, encrypted and presence channels.

## Against a local soketi server

```sh
npx @soketi/soketi start
# defaults: app id app-id, key app-key, secret app-secret, port 6001
```

Then:

```sh
cd example
flutter run -d macos \
  --dart-define=PUSHER_KEY=app-key \
  --dart-define=PUSHER_HOST=localhost \
  --dart-define=PUSHER_PORT=6001 \
  --dart-define=PUSHER_TLS=false \
  --dart-define=AUTH_ENDPOINT=http://localhost:3000/pusher/auth
```

Host names per target:

- iOS simulator, macOS, web: `localhost`
- Android emulator: `10.0.2.2`
- Physical device: your computer's LAN IP address

Plain `http://` / `ws://` to a non-localhost host on iOS needs an App Transport Security exception, and on macOS the
`com.apple.security.network.client` entitlement (already present in the example).

## Integration tests

See [integration_test/README.md](integration_test/README.md).
