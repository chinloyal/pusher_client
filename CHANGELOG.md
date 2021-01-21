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
