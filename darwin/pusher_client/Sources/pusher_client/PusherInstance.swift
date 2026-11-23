import Foundation
import PusherSwift

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

/// Receives protocol-shaped event maps (architecture.md section 5).
/// Implementations must be safe to call from any thread.
protocol EventEmitting: AnyObject {
    func emit(_ event: [String: Any])
}

/// Posts to the Flutter event sink on the main thread.
final class EventEmitter: EventEmitting {
    var sink: FlutterEventSink?

    func emit(_ event: [String: Any]) {
        if Thread.isMainThread {
            sink?(event)
        } else {
            DispatchQueue.main.async { [weak self] in self?.sink?(event) }
        }
    }
}

/// Invokes Dart's `authorize` and reports the raw outcome (map, `FlutterError`,
/// `FlutterMethodNotImplemented`) exactly once through `reply`.
typealias AuthorizeInvoker = (_ arguments: [String: Any], _ reply: @escaping (Any?) -> Void) -> Void

/// Guards a completion handler so it runs at most once.
final class OnceGuard {
    private let lock = NSLock()
    private var claimed = false

    /// Returns true only for the first caller.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Delegates channel authorization to Dart (architecture.md section 4.2).
final class DartAuthorizer: NSObject, Authorizer {
    static let defaultTimeout: TimeInterval = 30

    private let instanceId: String
    private let invoker: AuthorizeInvoker
    private let timeout: TimeInterval
    private let emitter: EventEmitting
    private let log: (String) -> Void

    init(
        instanceId: String, invoker: @escaping AuthorizeInvoker, emitter: EventEmitting,
        timeout: TimeInterval = DartAuthorizer.defaultTimeout, log: @escaping (String) -> Void = { _ in }
    ) {
        self.instanceId = instanceId
        self.invoker = invoker
        self.emitter = emitter
        self.timeout = timeout
        self.log = log
    }

    func fetchAuthValue(
        socketID: String, channelName: String, completionHandler: @escaping (PusherAuth?) -> Void
    ) {
        let once = OnceGuard()
        let fail: (AuthFailure) -> Void = { [weak self] failure in
            guard once.claim() else { return }
            guard let self = self else {
                completionHandler(nil)
                return
            }
            self.log("authorize failed for \(channelName): \(failure.message)")
            self.emitter.emit(EventPayloads.subscriptionError(
                instanceId: self.instanceId, channelName: channelName,
                message: failure.message, status: failure.status))
            completionHandler(nil)
        }

        let start = { [weak self] in
            guard let self = self else {
                if once.claim() { completionHandler(nil) }
                return
            }
            let arguments: [String: Any] = [
                "instanceId": self.instanceId,
                "channelName": channelName,
                "socketId": socketID,
            ]
            self.invoker(arguments) { raw in
                switch AuthResponse.parse(raw, channelName: channelName) {
                case .success(let auth):
                    if once.claim() { completionHandler(auth) }
                case .failure(let failure):
                    fail(failure)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.timeout) {
                fail(AuthFailure(message: "Authorization timed out after \(Int(self.timeout)) seconds.", status: nil))
            }
        }

        if Thread.isMainThread {
            start()
        } else {
            DispatchQueue.main.async(execute: start)
        }
    }
}

/// Per-instance `PusherDelegate`; captures the instanceId so every event is attributed.
final class InstanceDelegate: NSObject, PusherDelegate {
    let instanceId: String
    private let emitter: EventEmitting
    private let enableLogging: Bool
    weak var pusher: Pusher?

    init(instanceId: String, emitter: EventEmitting, enableLogging: Bool) {
        self.instanceId = instanceId
        self.emitter = emitter
        self.enableLogging = enableLogging
    }

    func changedConnectionState(from old: ConnectionState, to new: ConnectionState) {
        let socketId = new == .connected ? pusher?.connection.socketId : nil
        emitter.emit(EventPayloads.connectionStateChange(
            instanceId: instanceId,
            current: ConnectionStateMapper.normalize(new),
            previous: ConnectionStateMapper.normalize(old),
            socketId: socketId))
    }

    func receivedError(error: PusherError) {
        emitter.emit(EventPayloads.connectionError(
            instanceId: instanceId, message: error.message, code: error.code, exception: nil))
    }

    func failedToDecryptEvent(eventName: String, channelName: String, data: String?) {
        emitter.emit(EventPayloads.decryptionError(
            instanceId: instanceId, channelName: channelName, eventName: eventName,
            reason: "Failed to decrypt event data."))
    }

    func failedToSubscribeToChannel(name: String, response: URLResponse?, data: String?, error: NSError?) {
        // The library already delivers `pusher:subscription_error` through the global
        // callback; only log here to avoid duplicates.
        log("failed to subscribe to \(name): \(error?.localizedDescription ?? data ?? "unknown error")")
    }

    func debugLog(message: String) {
        log(message)
    }

    private func log(_ message: String) {
        guard enableLogging else { return }
        NSLog("[pusher_client:%@] %@", instanceId, message)
    }
}

/// One native Pusher client, owned by a Dart `PusherClient` through its `instanceId`.
final class PusherInstance {
    let instanceId: String
    let pusher: Pusher
    private let delegate: InstanceDelegate
    /// Retained here; the websocket only references it weakly.
    private var incomingMessageNormalizer: IncomingMessageNormalizer?
    private let emitter: EventEmitting
    private let enableLogging: Bool
    private var disposed = false

    init(
        instanceId: String, appKey: String, enableLogging: Bool, config: PusherOptionsConfig,
        emitter: EventEmitting, authorizeInvoker: @escaping AuthorizeInvoker,
        authTimeout: TimeInterval = DartAuthorizer.defaultTimeout
    ) throws {
        try config.validateSocketURL(appKey: appKey)

        self.instanceId = instanceId
        self.emitter = emitter
        self.enableLogging = enableLogging

        let authorizer = DartAuthorizer(
            instanceId: instanceId, invoker: authorizeInvoker, emitter: emitter, timeout: authTimeout,
            log: { message in
                if enableLogging { NSLog("[pusher_client:%@] %@", instanceId, message) }
            })
        let pusher = Pusher(key: appKey, options: config.clientOptions(authorizer: authorizer))
        pusher.connection.reconnectAttemptsMax = config.maxReconnectionAttempts
        pusher.connection.maxReconnectGapInSeconds = TimeInterval(config.maxReconnectGapInSeconds)
        pusher.connection.pongResponseTimeoutInterval = config.pongTimeout

        let delegate = InstanceDelegate(instanceId: instanceId, emitter: emitter, enableLogging: enableLogging)
        delegate.pusher = pusher
        pusher.delegate = delegate
        self.incomingMessageNormalizer = IncomingMessageNormalizer.install(on: pusher.connection)

        // One global binding for the lifetime of the instance: app/client events,
        // pusher:subscription_succeeded and pusher:subscription_error.
        pusher.bind(eventCallback: { [weak emitter] event in
            guard let payload = EventPayloads.forwarded(instanceId: instanceId, event: event) else { return }
            emitter?.emit(payload)
        })

        self.pusher = pusher
        self.delegate = delegate
        // Keep the authorizer alive for the lifetime of the instance as well.
        self.authorizer = authorizer
    }

    private var authorizer: DartAuthorizer?

    var socketId: String? {
        return pusher.connection.socketId
    }

    func connect() {
        pusher.connect()
    }

    func disconnect() {
        pusher.disconnect()
    }

    /// Idempotent for subscribed channels. The Dart layer only repeats
    /// `subscribe` for a known channel after `pusher:subscription_error`;
    /// PusherSwift keeps such a failed channel but never retries it, so an
    /// existing unsubscribed channel is dropped and subscribed afresh.
    func subscribe(channelName: String) {
        let connection = pusher.connection
        if let existing = connection.channels.find(name: channelName) {
            if existing.subscribed { return }
            connection.channels.channels.removeValue(forKey: channelName)
        }
        let id = instanceId
        let emitter = self.emitter
        let onCount: (Int) -> Void = { [weak emitter] count in
            emitter?.emit(EventPayloads.subscriptionCount(
                instanceId: id, channelName: channelName, count: count))
        }
        if ChannelKind(name: channelName) == .presence {
            _ = pusher.subscribeToPresenceChannel(
                channelName: channelName,
                onMemberAdded: { [weak emitter] member in
                    emitter?.emit(EventPayloads.memberAdded(
                        instanceId: id, channelName: channelName, userId: member.userId,
                        userInfo: member.userInfo))
                },
                onMemberRemoved: { [weak emitter] member in
                    emitter?.emit(EventPayloads.memberRemoved(
                        instanceId: id, channelName: channelName, userId: member.userId))
                },
                onSubscriptionCountChanged: onCount)
        } else {
            _ = pusher.subscribe(channelName, onSubscriptionCountChanged: onCount)
        }
    }

    /// Idempotent.
    func unsubscribe(channelName: String) {
        let connection = pusher.connection
        guard let channel = connection.channels.find(name: channelName) else { return }
        if channel.subscribed {
            pusher.unsubscribe(channelName)
            return
        }
        // PusherSwift ignores unsubscribe for channels that have not finished
        // subscribing (e.g. subscribed while offline or awaiting auth), which
        // would leave them to subscribe on the next connect. Drop the channel
        // locally and cancel any in-flight server-side subscription.
        connection.channels.channels.removeValue(forKey: channelName)
        if connection.connectionState == .connected {
            connection.sendEvent(event: "pusher:unsubscribe", data: ["channel": channelName])
        }
    }

    func trigger(channelName: String, eventName: String, data: String) throws {
        guard ChannelKind(name: channelName).supportsClientEvents else {
            throw PluginError(
                code: .triggerError,
                message: "Client events can only be triggered on private or presence channels.")
        }
        guard eventName.hasPrefix("client-") else {
            throw PluginError(code: .triggerError, message: "Client event names must start with 'client-'.")
        }
        guard let channel = pusher.connection.channels.find(name: channelName) else {
            throw PluginError(code: .triggerError, message: "Not subscribed to channel '\(channelName)'.")
        }
        channel.trigger(eventName: eventName, data: data)
    }

    /// Disconnects, unbinds and silences the instance; it must not be used afterwards.
    func dispose() {
        guard !disposed else { return }
        disposed = true
        // Prevent the library from reconnecting after the socket closes.
        pusher.connection.reconnectAttemptsMax = 0
        pusher.unbindAll()
        pusher.unsubscribeAll()
        if pusher.connection.connectionState == .connected {
            pusher.disconnect()
        } else {
            pusher.connection.socket?.disconnect()
        }
        pusher.delegate = nil
    }
}
