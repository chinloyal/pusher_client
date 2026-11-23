import PusherSwift
import XCTest

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

@testable import pusher_client

/// Collects events instead of talking to a Flutter event sink.
private final class RecordingEmitter: EventEmitting {
  var events: [[String: Any]] = []
  func emit(_ event: [String: Any]) { events.append(event) }
}

private func validInit(_ id: String = "i1", options: [String: Any] = [:]) -> FlutterMethodCall {
  var opts: [String: Any] = [
    "cluster": NSNull(), "host": NSNull(), "wsPort": 80, "wssPort": 443, "useTLS": true,
    "activityTimeout": 120_000, "pongTimeout": 30_000, "maxReconnectionAttempts": 6,
    "maxReconnectGapInSeconds": 30, "hasAuthorizer": true,
  ]
  options.forEach { opts[$0.key] = $0.value }
  return FlutterMethodCall(
    methodName: "init",
    arguments: ["instanceId": id, "appKey": "key", "enableLogging": false, "options": opts])
}

class RunnerTests: XCTestCase {

  // MARK: helpers

  private func call(
    _ plugin: PusherClientPlugin, _ method: String, _ arguments: Any?
  ) -> (replies: Int, value: Any?) {
    var replies = 0
    var value: Any?
    plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) {
      replies += 1
      value = $0
    }
    return (replies, value)
  }

  private func call(_ plugin: PusherClientPlugin, _ c: FlutterMethodCall) -> (replies: Int, value: Any?) {
    return call(plugin, c.method, c.arguments)
  }

  private func errorCode(_ value: Any?) -> String? {
    return (value as? FlutterError)?.code
  }

  // MARK: options mapping

  func testOptionsDefaultHost() throws {
    let config = try PusherOptionsConfig.parse(["useTLS": true])
    XCTAssertEqual(config.pusherHost.stringValue, "ws.pusherapp.com")
    XCTAssertEqual(config.port, 443)
  }

  func testClusterResolvesToPusherHost() throws {
    let config = try PusherOptionsConfig.parse(["cluster": "eu"])
    XCTAssertEqual(config.pusherHost.stringValue, "ws-eu.pusher.com")
  }

  func testHostWinsOverCluster() throws {
    let config = try PusherOptionsConfig.parse(["cluster": "eu", "host": "localhost", "useTLS": false, "wsPort": 6001])
    XCTAssertEqual(config.pusherHost.stringValue, "localhost")
    XCTAssertEqual(config.port, 6001)
    XCTAssertFalse(config.useTLS)
  }

  func testNullHostAndClusterAreIgnored() throws {
    let config = try PusherOptionsConfig.parse(["cluster": NSNull(), "host": NSNull()])
    XCTAssertNil(config.host)
    XCTAssertNil(config.cluster)
  }

  func testPortSelectionFollowsTLS() throws {
    let tls = try PusherOptionsConfig.parse(["useTLS": true, "wsPort": 81, "wssPort": 444])
    let plain = try PusherOptionsConfig.parse(["useTLS": false, "wsPort": 81, "wssPort": 444])
    XCTAssertEqual(tls.port, 444)
    XCTAssertEqual(plain.port, 81)
  }

  func testTimeoutsConvertedToSeconds() throws {
    let config = try PusherOptionsConfig.parse(["activityTimeout": 45_000, "pongTimeout": 5_000])
    XCTAssertEqual(config.activityTimeout, 45)
    XCTAssertEqual(config.pongTimeout, 5)
  }

  func testClientOptionsValues() throws {
    let config = try PusherOptionsConfig.parse(["host": "h.example", "useTLS": false, "wsPort": 6001])
    let options = config.clientOptions(authorizer: DartAuthorizer(
      instanceId: "x", invoker: { _, _ in }, emitter: RecordingEmitter()))
    XCTAssertEqual(options.host, "h.example")
    XCTAssertEqual(options.port, 6001)
    XCTAssertFalse(options.useTLS)
    XCTAssertEqual(options.activityTimeout, 120)
    if case .authorizer = options.authMethod {} else { XCTFail("expected authorizer auth method") }
  }

  func testInvalidOptionsAreRejected() {
    XCTAssertThrowsError(try PusherOptionsConfig.parse(nil))
    XCTAssertThrowsError(try PusherOptionsConfig.parse(["wsPort": "80"]))
    XCTAssertThrowsError(try PusherOptionsConfig.parse(["wssPort": 0]))
    XCTAssertThrowsError(try PusherOptionsConfig.parse(["useTLS": "yes"]))
  }

  func testInvalidHostFailsInitInsteadOfCrashing() throws {
    let config = try PusherOptionsConfig.parse(["host": "bad host name"])
    XCTAssertThrowsError(try config.validateSocketURL(appKey: "key")) {
      XCTAssertEqual(($0 as? PluginError)?.code, .initError)
    }
    XCTAssertThrowsError(try PusherOptionsConfig.parse([:]).validateSocketURL(appKey: "bad key"))
    XCTAssertNoThrow(try PusherOptionsConfig.parse(["host": "localhost"]).validateSocketURL(appKey: "app-key"))
  }

  // MARK: state normalisation

  func testConnectionStateNormalisation() {
    XCTAssertEqual(ConnectionStateMapper.normalize(.connecting), "CONNECTING")
    XCTAssertEqual(ConnectionStateMapper.normalize(.connected), "CONNECTED")
    XCTAssertEqual(ConnectionStateMapper.normalize(.disconnecting), "DISCONNECTING")
    XCTAssertEqual(ConnectionStateMapper.normalize(.disconnected), "DISCONNECTED")
    XCTAssertEqual(ConnectionStateMapper.normalize(.reconnecting), "RECONNECTING")
  }

  func testDelegateEmitsNormalisedStateChange() {
    let emitter = RecordingEmitter()
    let delegate = InstanceDelegate(instanceId: "a", emitter: emitter, enableLogging: false)
    delegate.changedConnectionState(from: .disconnected, to: .connecting)
    XCTAssertEqual(emitter.events.count, 1)
    let e = emitter.events[0]
    XCTAssertEqual(e["instanceId"] as? String, "a")
    XCTAssertEqual(e["type"] as? String, "connectionStateChange")
    XCTAssertEqual(e["currentState"] as? String, "CONNECTING")
    XCTAssertEqual(e["previousState"] as? String, "DISCONNECTED")
    XCTAssertTrue(e["socketId"] is NSNull)
  }

  // MARK: payloads

  func testConnectionErrorPayload() {
    let e = EventPayloads.connectionError(instanceId: "a", message: "boom", code: 4001, exception: nil)
    XCTAssertEqual(e["type"] as? String, "connectionError")
    XCTAssertEqual(e["code"] as? String, "4001")
    XCTAssertEqual(e["message"] as? String, "boom")
    XCTAssertTrue(e["exception"] is NSNull)
    XCTAssertTrue(EventPayloads.connectionError(instanceId: "a", message: nil, code: nil, exception: nil)["code"] is NSNull)
  }

  func testEventPayloadShape() {
    let e = EventPayloads.event(instanceId: "a", channelName: "c", eventName: "e", data: "{}", userId: nil)
    XCTAssertEqual(e["type"] as? String, "event")
    XCTAssertEqual(e["channelName"] as? String, "c")
    XCTAssertEqual(e["eventName"] as? String, "e")
    XCTAssertEqual(e["data"] as? String, "{}")
    XCTAssertTrue(e["userId"] is NSNull)
  }

  func testSubscriptionErrorPayload() throws {
    let e = EventPayloads.subscriptionError(instanceId: "a", channelName: "private-x", message: "nope", status: 403)
    XCTAssertEqual(e["eventName"] as? String, "pusher:subscription_error")
    let body = try XCTUnwrap(parse(e["data"]))
    XCTAssertEqual(body["type"] as? String, "AuthError")
    XCTAssertEqual(body["error"] as? String, "nope")
    XCTAssertEqual(body["status"] as? Int, 403)
    let noStatus = EventPayloads.subscriptionError(instanceId: "a", channelName: "c", message: "m", status: nil)
    XCTAssertTrue(try XCTUnwrap(parse(noStatus["data"]))["status"] is NSNull)
  }

  func testMemberAddedHasRealJsonUserInfo() throws {
    let info: [String: Any] = ["name": "Ann", "tags": ["a", "b"], "age": 3]
    let e = EventPayloads.memberAdded(instanceId: "a", channelName: "presence-r", userId: "u1", userInfo: info)
    XCTAssertEqual(e["eventName"] as? String, "pusher:member_added")
    XCTAssertEqual(e["userId"] as? String, "u1")
    let body = try XCTUnwrap(parse(e["data"]))
    XCTAssertEqual(body["user_id"] as? String, "u1")
    let userInfo = try XCTUnwrap(body["user_info"] as? [String: Any])
    XCTAssertEqual(userInfo["name"] as? String, "Ann")
    XCTAssertEqual(userInfo["tags"] as? [String], ["a", "b"])
    XCTAssertEqual(userInfo["age"] as? Int, 3)
  }

  func testMemberAddedWithoutInfoIsNull() throws {
    let e = EventPayloads.memberAdded(instanceId: "a", channelName: "presence-r", userId: "u1", userInfo: nil)
    XCTAssertTrue(try XCTUnwrap(parse(e["data"]))["user_info"] is NSNull)
    let bad = EventPayloads.memberAdded(instanceId: "a", channelName: "presence-r", userId: "u1", userInfo: Date())
    XCTAssertTrue(try XCTUnwrap(parse(bad["data"]))["user_info"] is NSNull)
  }

  func testMemberRemovedPayload() throws {
    let e = EventPayloads.memberRemoved(instanceId: "a", channelName: "presence-r", userId: "u2")
    XCTAssertEqual(e["eventName"] as? String, "pusher:member_removed")
    XCTAssertEqual(e["userId"] as? String, "u2")
    XCTAssertEqual(try XCTUnwrap(parse(e["data"]))["user_id"] as? String, "u2")
  }

  func testSubscriptionCountPayload() throws {
    let e = EventPayloads.subscriptionCount(instanceId: "a", channelName: "c", count: 7)
    XCTAssertEqual(e["eventName"] as? String, "pusher:subscription_count")
    XCTAssertEqual(try XCTUnwrap(parse(e["data"]))["subscription_count"] as? Int, 7)
  }

  func testDecryptionErrorPayload() throws {
    let emitter = RecordingEmitter()
    let delegate = InstanceDelegate(instanceId: "a", emitter: emitter, enableLogging: false)
    delegate.failedToDecryptEvent(eventName: "evt", channelName: "private-encrypted-x", data: nil)
    let e = try XCTUnwrap(emitter.events.first)
    XCTAssertEqual(e["eventName"] as? String, "pusher:decryption_error")
    XCTAssertEqual(e["channelName"] as? String, "private-encrypted-x")
    XCTAssertEqual(try XCTUnwrap(parse(e["data"]))["event"] as? String, "evt")
    XCTAssertNotNil(try XCTUnwrap(parse(e["data"]))["reason"] as? String)
  }

  func testChannelKinds() {
    XCTAssertEqual(ChannelKind(name: "news"), .public)
    XCTAssertEqual(ChannelKind(name: "private-x"), .private)
    XCTAssertEqual(ChannelKind(name: "private-encrypted-x"), .privateEncrypted)
    XCTAssertEqual(ChannelKind(name: "presence-x"), .presence)
    XCTAssertTrue(ChannelKind.private.supportsClientEvents)
    XCTAssertTrue(ChannelKind.presence.supportsClientEvents)
    XCTAssertFalse(ChannelKind.privateEncrypted.supportsClientEvents)
    XCTAssertFalse(ChannelKind.public.supportsClientEvents)
  }

  // MARK: auth response parsing

  func testAuthResponseSuccess() throws {
    let result = AuthResponse.parse(
      ["auth": "k:sig", "channel_data": "{\"user_id\":\"1\"}", "shared_secret": "s"], channelName: "presence-r")
    let auth = try result.get()
    XCTAssertEqual(auth.auth, "k:sig")
    XCTAssertEqual(auth.channelData, "{\"user_id\":\"1\"}")
    XCTAssertEqual(auth.sharedSecret, "s")
  }

  func testAuthResponseFailures() {
    let flutterError = FlutterError(code: "AUTH_ERROR", message: "denied", details: ["status": 403])
    XCTAssertEqual(
      AuthResponse.parse(flutterError, channelName: "private-a").failureValue,
      AuthFailure(message: "denied", status: 403))
    XCTAssertNotNil(AuthResponse.parse(FlutterMethodNotImplemented, channelName: "private-a").failureValue)
    XCTAssertNotNil(AuthResponse.parse(nil, channelName: "private-a").failureValue)
    XCTAssertNotNil(AuthResponse.parse(["nope": 1], channelName: "private-a").failureValue)
    // presence requires channel_data
    XCTAssertNotNil(AuthResponse.parse(["auth": "x"], channelName: "presence-a").failureValue)
    XCTAssertNoThrow(try AuthResponse.parse(["auth": "x"], channelName: "private-a").get())
  }

  // MARK: authorizer

  func testAuthorizerSuccessCompletesOnce() {
    let emitter = RecordingEmitter()
    var invoked: [String: Any]?
    let authorizer = DartAuthorizer(
      instanceId: "a",
      invoker: { args, reply in
        invoked = args
        reply(["auth": "k:s"])
        reply(["auth": "second"])  // must be ignored
      }, emitter: emitter)
    var results: [PusherAuth?] = []
    authorizer.fetchAuthValue(socketID: "1.2", channelName: "private-a") { results.append($0) }
    XCTAssertEqual(invoked?["instanceId"] as? String, "a")
    XCTAssertEqual(invoked?["channelName"] as? String, "private-a")
    XCTAssertEqual(invoked?["socketId"] as? String, "1.2")
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first??.auth, "k:s")
    XCTAssertTrue(emitter.events.isEmpty)
  }

  func testAuthorizerErrorEmitsSubscriptionErrorAndCompletesNil() throws {
    let emitter = RecordingEmitter()
    let authorizer = DartAuthorizer(
      instanceId: "a",
      invoker: { _, reply in
        reply(FlutterError(code: "AUTH_ERROR", message: "forbidden", details: ["status": 403]))
      }, emitter: emitter)
    var completions = 0
    var last: PusherAuth?
    authorizer.fetchAuthValue(socketID: "1.2", channelName: "private-a") {
      completions += 1
      last = $0
    }
    XCTAssertEqual(completions, 1)
    XCTAssertNil(last)
    XCTAssertEqual(emitter.events.count, 1)
    let e = emitter.events[0]
    XCTAssertEqual(e["eventName"] as? String, "pusher:subscription_error")
    XCTAssertEqual(e["channelName"] as? String, "private-a")
    let body = try XCTUnwrap(parse(e["data"]))
    XCTAssertEqual(body["error"] as? String, "forbidden")
    XCTAssertEqual(body["status"] as? Int, 403)
  }

  func testAuthorizerNotImplementedFails() {
    let emitter = RecordingEmitter()
    let authorizer = DartAuthorizer(
      instanceId: "a", invoker: { _, reply in reply(FlutterMethodNotImplemented) }, emitter: emitter)
    var last: PusherAuth? = PusherAuth(auth: "x")
    authorizer.fetchAuthValue(socketID: "1", channelName: "private-a") { last = $0 }
    XCTAssertNil(last)
    XCTAssertEqual(emitter.events.count, 1)
  }

  func testAuthorizerTimeoutCompletesOnceAndIgnoresLateReply() {
    let emitter = RecordingEmitter()
    var lateReply: ((Any?) -> Void)?
    let authorizer = DartAuthorizer(
      instanceId: "a", invoker: { _, reply in lateReply = reply }, emitter: emitter, timeout: 0.1)
    var completions = 0
    let done = expectation(description: "timeout")
    authorizer.fetchAuthValue(socketID: "1", channelName: "private-a") { _ in
      completions += 1
      done.fulfill()
    }
    wait(for: [done], timeout: 3)
    lateReply?(["auth": "too late"])
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(emitter.events.count, 1)
    XCTAssertEqual(emitter.events[0]["eventName"] as? String, "pusher:subscription_error")
  }

  // MARK: method dispatch

  func testUnknownMethodIsNotImplemented() {
    let plugin = PusherClientPlugin()
    let r = call(plugin, "bogus", nil)
    XCTAssertEqual(r.replies, 1)
    XCTAssertTrue((r.value as AnyObject) === FlutterMethodNotImplemented)
  }

  func testInvalidArgumentsRepliesOnceWithErrorCode() {
    let plugin = PusherClientPlugin()
    for (method, args) in [
      ("init", nil), ("init", "str"), ("init", ["instanceId": "a"]),
      ("connect", nil), ("subscribe", ["instanceId": 5]), ("trigger", [:]),
    ] as [(String, Any?)] {
      let r = call(plugin, method, args)
      XCTAssertEqual(r.replies, 1, method)
      XCTAssertEqual(errorCode(r.value), "INVALID_ARGUMENTS", method)
    }
  }

  func testNoInstanceErrors() {
    let plugin = PusherClientPlugin()
    for method in ["connect", "disconnect", "getSocketId"] {
      let r = call(plugin, method, ["instanceId": "missing"])
      XCTAssertEqual(r.replies, 1)
      XCTAssertEqual(errorCode(r.value), "NO_INSTANCE", method)
    }
    XCTAssertEqual(errorCode(call(plugin, "subscribe", ["instanceId": "m", "channelName": "c"]).value), "NO_INSTANCE")
    XCTAssertEqual(errorCode(call(plugin, "unsubscribe", ["instanceId": "m", "channelName": "c"]).value), "NO_INSTANCE")
  }

  func testDisposeAndDisposeAllAreNoOpsForUnknownInstances() {
    let plugin = PusherClientPlugin()
    let a = call(plugin, "dispose", ["instanceId": "missing"])
    XCTAssertEqual(a.replies, 1)
    XCTAssertNil(a.value)
    let b = call(plugin, "disposeAll", [:])
    XCTAssertEqual(b.replies, 1)
    XCTAssertNil(b.value)
  }

  func testInitInvalidHostIsInitError() {
    let plugin = PusherClientPlugin()
    let r = call(plugin, validInit(options: ["host": "not a host"]))
    XCTAssertEqual(r.replies, 1)
    XCTAssertEqual(errorCode(r.value), "INIT_ERROR")
    XCTAssertTrue(plugin.instances.isEmpty)
  }

  func testInstanceLifecycleWithoutNetwork() {
    let plugin = PusherClientPlugin()
    XCTAssertNil(call(plugin, validInit()).value)
    XCTAssertEqual(plugin.instances.count, 1)

    // getSocketId before connecting is null
    let sid = call(plugin, "getSocketId", ["instanceId": "i1"])
    XCTAssertEqual(sid.replies, 1)
    XCTAssertNil(sid.value)

    // subscribe / unsubscribe are accepted offline and idempotent
    for name in ["news", "private-a", "presence-r"] {
      XCTAssertNil(call(plugin, "subscribe", ["instanceId": "i1", "channelName": name]).value)
      XCTAssertNil(call(plugin, "subscribe", ["instanceId": "i1", "channelName": name]).value)
    }
    XCTAssertNotNil(plugin.instances["i1"]?.pusher.connection.channels.find(name: "presence-r") as? PusherPresenceChannel)
    XCTAssertNil(call(plugin, "unsubscribe", ["instanceId": "i1", "channelName": "news"]).value)
    XCTAssertNil(call(plugin, "unsubscribe", ["instanceId": "i1", "channelName": "never"]).value)

    // re-init with the same id replaces the instance
    let first = plugin.instances["i1"]
    XCTAssertNil(call(plugin, validInit()).value)
    XCTAssertEqual(plugin.instances.count, 1)
    XCTAssertFalse(plugin.instances["i1"] === first)

    XCTAssertNil(call(plugin, "dispose", ["instanceId": "i1"]).value)
    XCTAssertTrue(plugin.instances.isEmpty)
    XCTAssertEqual(errorCode(call(plugin, "connect", ["instanceId": "i1"]).value), "NO_INSTANCE")
  }

  func testTriggerValidation() {
    let plugin = PusherClientPlugin()
    _ = call(plugin, validInit())
    for name in ["private-a", "presence-r", "private-encrypted-e", "pub"] {
      _ = call(plugin, "subscribe", ["instanceId": "i1", "channelName": name])
    }
    func trigger(_ channel: String, _ event: String, _ data: Any?) -> (replies: Int, value: Any?) {
      return call(plugin, "trigger", ["instanceId": "i1", "channelName": channel, "eventName": event, "data": data as Any])
    }
    // public and encrypted channels refuse client events
    XCTAssertEqual(errorCode(trigger("pub", "client-x", "{}").value), "TRIGGER_ERROR")
    XCTAssertEqual(errorCode(trigger("private-encrypted-e", "client-x", "{}").value), "TRIGGER_ERROR")
    // missing prefix
    XCTAssertEqual(errorCode(trigger("private-a", "x", "{}").value), "TRIGGER_ERROR")
    // not subscribed
    XCTAssertEqual(errorCode(trigger("private-zzz", "client-x", "{}").value), "TRIGGER_ERROR")
    // data must be a string
    XCTAssertEqual(errorCode(trigger("private-a", "client-x", 5).value), "INVALID_ARGUMENTS")
    // valid: replies once with null (queued until the channel is subscribed)
    let ok = trigger("private-a", "client-x", "{\"a\":1}")
    XCTAssertEqual(ok.replies, 1)
    XCTAssertNil(ok.value)
    XCTAssertEqual(trigger("presence-r", "client-y", "{}").replies, 1)
  }

  func testForwardedEvents() {
    XCTAssertNil(EventPayloads.forwarded(
      instanceId: "a", channelName: nil, eventName: "pusher:error", data: nil, userId: nil))
    let e = EventPayloads.forwarded(
      instanceId: "a", channelName: "c", eventName: "pusher:subscription_succeeded", data: "{}", userId: nil)
    XCTAssertEqual(e?["eventName"] as? String, "pusher:subscription_succeeded")
    XCTAssertEqual(e?["data"] as? String, "{}")
  }

  // MARK: utilities

  private func parse(_ raw: Any?) -> [String: Any]? {
    guard let string = raw as? String, let data = string.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  // MARK: - SubscriptionDataNormalizer

  func testNormalizerAddsDataToDataLessSubscriptionSucceeded() throws {
    let raw = #"{"event":"pusher_internal:subscription_succeeded","channel":"private-a"}"#
    let out = SubscriptionDataNormalizer.normalize(raw)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    XCTAssertEqual(json["event"] as? String, "pusher_internal:subscription_succeeded")
    XCTAssertEqual(json["channel"] as? String, "private-a")
    XCTAssertEqual(json["data"] as? String, "{}")
  }

  func testNormalizerTreatsNullDataAsMissing() throws {
    let raw = #"{"event":"pusher_internal:subscription_succeeded","channel":"a","data":null}"#
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(SubscriptionDataNormalizer.normalize(raw).utf8))
        as? [String: Any])
    XCTAssertEqual(json["data"] as? String, "{}")
  }

  func testNormalizerLeavesMessagesWithDataUntouched() {
    let presence =
      #"{"event":"pusher_internal:subscription_succeeded","channel":"presence-a","data":"{\"presence\":{\"count\":1}}"}"#
    XCTAssertEqual(SubscriptionDataNormalizer.normalize(presence), presence)
    let other = #"{"event":"my-event","channel":"a"}"#
    XCTAssertEqual(SubscriptionDataNormalizer.normalize(other), other)
    let mention = #"{"event":"my-event","channel":"a","data":"pusher_internal:subscription_succeeded"}"#
    XCTAssertEqual(SubscriptionDataNormalizer.normalize(mention), mention)
    XCTAssertEqual(SubscriptionDataNormalizer.normalize("not json"), "not json")
  }

}

private extension Result {
  var failureValue: Failure? {
    if case .failure(let e) = self { return e }
    return nil
  }
}
