# AGENTS.md

Guidance for AI coding agents (Claude Code and sub-agents) working on
`pusher_client`, a Flutter plugin for Pusher Channels (Android, iOS, macOS, web).

## Orchestration model (owner's standing instruction)

* **Opus is the orchestrator.** The Opus session owns planning, architecture,
  protocol design, triage of GitHub issues, anything requiring heavy reasoning,
  review of every sub-agent's output, and all commits.
* **Implementation goes to Sonnet 5.5 at medium effort** when the task is
  well-specified and does not need further design: spawn with
  `model: "sonnet"`, `effort: "medium"`, and a brief that names the files, the
  spec sections to follow, the commands that prove it works, and what "done" means.
* **Opus keeps complex work for itself** — anything that needs judgement,
  cross-platform design, debugging a non-obvious failure, or where a wrong
  call would ripple across platforms (e.g. Gradle/AGP compatibility, the
  Dart↔native protocol, release decisions).
* If a Sonnet agent hits a design question, it stops and reports back rather
  than inventing protocol; Opus decides and updates `doc/architecture.md`.
* Sub-agents never commit, push, publish, comment on GitHub, or change global
  tooling config. They do not run `git add -A` (the repo root holds an
  unrelated untracked `sample.txt` that must never be committed).
* Parallel agents must own disjoint files. `pubspec.yaml` and
  `doc/architecture.md` are owned by Opus.

## Source of truth

* `doc/architecture.md` — public API, the Dart↔native protocol (method names,
  argument maps, event payloads, error codes) and per-platform requirements.
  Change it first, then every implementation and its tests.

## Layout

```
lib/                      Dart API + platform abstraction (+ web impl in lib/src/web)
android/                  Kotlin implementation (pusher-java-client)
darwin/                   Shared Swift implementation for iOS + macOS (PusherSwift)
example/                  Demo app, integration tests, native unit-test hosts
test/                     Dart unit tests
doc/architecture.md       Design + protocol
```

## Commands

```bash
flutter pub get && flutter analyze && flutter test            # Dart
dart format --set-exit-if-changed lib test example/lib example/integration_test
cd example && flutter build apk --debug                        # Android build
cd example/android && ./gradlew :pusher_client:testDebugUnitTest   # Kotlin unit tests
cd example && flutter build ios --simulator --debug            # iOS build
cd example && flutter build macos --debug                      # macOS build
cd example && flutter build web                                 # Web build
flutter pub publish --dry-run                                   # Package validation
```

Integration tests need a local Pusher-protocol server — see
`example/integration_test/README.md`.

## Conventions

* Dart: `flutter_lints`, `dart format`, no `print` in library code
  (use `dart:developer` `log` behind `enableLogging`).
* Native code replies to every `MethodChannel` call exactly once, never
  force-unwraps platform input, and touches Flutter channels on the main thread.
* Every behaviour change ships with tests on each affected platform.
* Keep `CHANGELOG.md` and `README.md` in sync with user-visible changes.
