# Pusher Channels Flutter Client

[![pub version](https://img.shields.io/pub/v/pusher_client.svg?logo=dart)](https://pub.dartlang.org/packages/pusher_client)
[![GitHub license](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/chinloyal/pusher_client/master/LICENSE)
![Languages](https://img.shields.io/badge/languages-dart%20%7C%20kotlin%20%7C%20swift-blueviolet.svg)
[![Twitter](https://img.shields.io/badge/twitter-@chinloyal-blue.svg?style=flat&logo=twitter)](https://twitter.com/chinloyal)

A Pusher Channels client plugin for Flutter targeting Android and iOS. It wraps
[pusher-websocket-java](https://github.com/pusher/pusher-websocket-java) v2.2.5 and [pusher-websocket-swift](https://github.com/pusher/pusher-websocket-swift) v8.0.0.

For tutorials and more in-depth information about Pusher Channels, visit the [official docs](https://pusher.com/docs/channels).

This client works with official pusher servers and laravel self hosted pusher websocket server ([laravel-websockets](https://github.com/beyondcode/laravel-websockets)). 

## Supported Platforms & Deployment Targets

- Android API 16 and above
- iOS 9.0 and above

## Table of Contents

- [Installation](#installation)
- [Configuration](#configuration)
    - [For iOS](#for-ios)
    - [For Android](#for-android)
- [API Overview](#api-overview)
- [The Pusher Constructor](#the-pusher-constructor)
- [Pusher Options Config](#pusher-options-config)
- [Reconnecting](#reconnecting)
- [Disconnecting](#disconnecting)
- [Subscribing To Channels](#subscribing-to-channels)
    - [Public Channels](#public-channels)
    - [Private Channels](#private-channels)
	- [Private Encrypted Channels](#private-encrypted-channels)
	- [Presence Channels](#presence-channels)
- [Binding To Events](#bindings-to-events)
    - [Callback Parameters](#callback-parameters)
    - [Unbind Channel Events](#unbind-channel-events)
- [Triggering Client Events](#triggering-client-events)
- [Accessing The Connection Socket ID](#accessing-the-connection-socket-id)
- [Resolve Common Issues](#resolve-common-issues)
## Installation

Add to your pubspec.yaml

```yaml
dependencies:
    pusher_client: ^2.0.0
```

## Configuration

### For iOS

Set the minimum deployment target in the Podfile to 9.0. Go to `ios/Podfile`, then uncomment this line:

```Podfile
# platform :ios, '8.0'
```

Change it to:

```Podfile
platform :ios, '9.0'
```

You may have an issue subscribing to private channels if you're using a local pusher server like [laravel-websockets](https://github.com/beyondcode/laravel-websockets), to fix this go to `ios/Runner/Info.plist` and add:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

If you know which domains you will connect to add:

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

### For Android

If you have enabled code obfuscation with R8 or proguard, you need to add the following rule in `android/app/build.gradle`:

```gradle
buildTypes {
  release {
    minifyEnabled true
    proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
  }
}
```

Then in `android/app/proguard-rules.pro`:

```pro
-keep class com.github.chinloyal.pusher_client.** { *; }
```


## API Overview

Here's the API in a nutshell.

```dart
PusherOptions options = PusherOptions(
    host: 'example.com',
    wsPort: 6001,
    encrypted: false,
    auth: PusherAuth(
        'http://example.com/auth',
        headers: {
            'Authorization': 'Bearer $token',
        },
    ),
);

PusherClient pusher = PusherClient(
    YOUR_APP_KEY,
    options,
    autoConnect: false
);

// connect at a later time than at instantiation.
pusher.connect();

pusher.onConnectionStateChange((state) {
    print("previousState: ${state.previousState}, currentState: ${state.currentState}");
});

pusher.onConnectionError((error) {
    print("error: ${error.message}");
});

// Subscribe to a private channel
Channel channel = pusher.subscribe("private-orders");

// Bind to listen for events called "order-status-updated" sent to "private-orders" channel
channel.bind("order-status-updated", (PusherEvent event) {
    print(event.data);
});

// Unsubscribe from channel
pusher.unsubscribe("private-orders");

// Disconnect from pusher service
pusher.disconnect();

```
More information in reference format can be found below.


## The Pusher Constructor

The constructor takes an application key which you can get from the app's API Access section in the Pusher Channels dashboard, and a pusher options object.

```dart
PusherClient pusher = PusherClient(YOUR_APP_KEY, PusherOptions());
```


If you are going to use [private](https://pusher.com/docs/channels/using_channels/private-channels), [presence](https://pusher.com/docs/channels/using_channels/presence-channels) or [encrypted](https://pusher.com/docs/channels/using_channels/encrypted-channels) channels then you will need to provide a `PusherAuth` to be used when authenticating subscriptions. In order to do this you need to pass in a `PusherOptions` object which has had an `auth` set.

```dart
PusherAuth auth = PusherAuth(
    // for auth endpoint use full url
    'http://example.com/auth',
    headers: {
        'Authorization': 'Bearer $token',
    },
);

PusherOptions options = PusherOptions(
    auth: auth
);

PusherClient pusher = PusherClient(YOUR_APP_KEY, options);
```

To disable logging and auto connect do this:

```dart
PusherClient pusher = PusherClient(
    YOUR_APP_KEY,
    options,
    enableLogging: false,
    autoConnect: false,
);
```

If auto connect is disabled then you can manually connect using `connect()` on the pusher instance.

## Pusher Options Config

Most of the functionality of this plugin is configured through the PusherOptions object. You configure it by setting parameters on the object before passing it to the Pusher client. Below is a table containing all of the properties you can set.

| Method                      | Parameter         | Description                                                                                                                                   |
|-----------------------------|-------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| encrypted                | bool           | Whether the connection should be made with TLS or not.                                                                                   |
| auth              | PusherAuth | Sets the authorization options to be used when authenticating private, private-encrypted and presence channels.                                                             |
| host                     | String            | The host to which connections will be made.                                                                                                   |
| wsPort                   | int               | The port to which unencrypted connections will be made. Automatically set correctly.                                                          |
| wssPort                  | int               | The port to which encrypted connections will be made. Automatically set correctly.                                                            |
| cluster                  | String            | Sets the cluster the client will connect to, thereby setting the Host and Port correctly.                                                     |
| activityTimeout          | int              | The number of milliseconds of inactivity at which a "ping" will be triggered to check the connection. The default value is 120,000.           |
| pongTimeout              | int              | The number of milliseconds the client waits to receive a "pong" response from the server before disconnecting. The default value is 30,000.   |
| maxReconnectionAttempts  | int               | Number of reconnection attempts that will be made when `pusher.connect()` is called, after which the client will give up.                       |
| maxReconnectGapInSeconds | int               | The delay in two reconnection extends exponentially (1, 2, 4, .. seconds) This property sets the maximum inbetween two reconnection attempts. |

## Reconnecting

The `connect()` method is also used to re-connect in case the connection has been lost, for example if a device loses reception. Note that the state of channel subscriptions and event bindings will be preserved while disconnected and re-negotiated with the server once a connection is re-established.

## Disconnecting

```dart
pusher.disconnect();
```

After disconnection the `PusherClient` instance will release any internally allocated resources (threads and network connections)

## Subscribing To Channels

Channels use the concept of [channels](https://pusher.com/docs/channels/using_channels/channels) as a way of subscribing to data. They are identified and subscribed to by a simple name. Events are bound to a channel and are also identified by name.

As mentioned above, channel subscriptions need only be registered once by the `PusherClient` instance. They are preserved across disconnection and re-established with the server on reconnect. They should NOT be re-registered. They may, however, be registered with a `PusherClient` instance before the first call to `connect` - they will be completed with the server as soon as a connection becomes available.

### Public Channels

The default method for subscribing to a channel involves invoking the subscribe method of your client object:

```dart
Channel channel = pusher.subscribe("my-channel");
```
This returns a `Channel` object, which events can be bound to.

### Private Channels

Private channels are created in exactly the same way as public channels, except that they reside in the _'private-'_ namespace. This means prefixing the channel name:

```dart
Channel privateChannel = pusher.subscribe("private-status-update");
```

Subscribing to private channels involves the client being authenticated. See [The Pusher Constructor](#the-pusher-constructor) section for the authenticated channel example for more information.

### Private Encrypted Channels

Similar to Private channels, you can also subscribe to a private encrypted channel. This plugin fully supports end-to-end encryption. This means that only you and your connected clients will be able to read your messages. Pusher cannot decrypt them. These channels must be prefixed with _'private-encrypted-'_

Like with private channels, you must provide an authentication endpoint. That endpoint must be using a [server client that supports end-to-end encryption](https://pusher.com/docs/channels/using_channels/encrypted-channels#server). There is a [demonstration endpoint to look at using nodejs](https://github.com/pusher/pusher-channels-auth-example#using-e2e-encryption).

### Presence Channels

Presence channels are channels whose names are prefixed by _'presence-'_. Presence channels also need to be authenticated.

```dart
Channel presenceChannel = pusher.subscribe("presence-another-channel");
```

## Binding To Events

There are two types of events that occur on channel subscriptions.

1. Protocol related events such as those triggered when a subscription succeeds, for example "pusher:subscription_succeeded"
2. Application events that have been triggered by code within your app

```dart
Channel channel = pusher.subscribe("private-orders");

channel.bind("order-status-updated", (PusherEvent event) {
    print(event.data);
});
```

### Callback Parameters

The callbacks you bind receive a `PusherEvent`:

|  Property            | Type           | Description  |
| ------------------ |--------------| ------------
| `eventName`       | `String`      | The name of the event. |
| `channelName`   | `String`    | The name of the channel that the event was triggered on. (Optional) |
| `data`                | `String`     | The data that was passed to `trigger`, encoded as a string. If you passed an object then that will have been serialized to a JSON string which you can parse as necessary. (Optional)|
| `userId`            | `String`     | The ID of the user who triggered the event. This is only available for client events triggered on presence channels. (Optional)|

### Unbind Channel Events

You can unbind from an event by doing:

```dart
channel.unbind("order-status-updated");
```

## Triggering Client Events

Once a private or presence subscription has been authorized and the subscription has succeeded, it is possible to trigger events on those channels.

Events triggered by clients are called [client events](https://pusher.com/docs/channels/using_channels/events#triggering-client-events). Because they are being triggered from a client which may not be trusted there are a number of enforced rules when using them. Some of these rules include:

- Event names must have a _'client-'_ prefix
- Rate limits
- You can only trigger an event when the subscription has succeeded

```dart
channel.bind("pusher:subscription_succeeded", (PusherEvent event) {
    channel.trigger("client-istyping", {"name": "Bob"});
});
```

For full details see the [client events documentation](https://pusher.com/docs/channels/using_channels/events#triggering-client-events).


## Accessing The Connection Socket ID

Once connected you can access a unique identifier for the current client's connection. This is known as the **socket Id**. You can access the value once the connection has been established as follows:

```dart
String socketId = pusher.getSocketId();
```

For more information on how and why there is a socket Id see the documentation on authenticating users and [excluding recipients](https://pusher.com/docs/channels/server_api/excluding-event-recipients).

## Resolve Common Issues

### iOS doesn't log when enableLogging is set to true

iOS logging doesn't seem to output to flutter console, however if you run the
app from Xcode you should be able to see the logs.


### Subscribing to private channels with iOS

If using a local pusher server but are unable to subscribe to a private channel
then add this to your ios/Runner/Info.plist:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

If you know which domains you will connect to add:

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
