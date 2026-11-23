import Foundation
import PusherSwift

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

// MARK: - Errors (architecture.md section 7)

/// Error codes returned to Dart as `FlutterError`s.
enum PluginErrorCode: String {
    case initError = "INIT_ERROR"
    case noInstance = "NO_INSTANCE"
    case invalidArguments = "INVALID_ARGUMENTS"
    case subscribeError = "SUBSCRIBE_ERROR"
    case unsubscribeError = "UNSUBSCRIBE_ERROR"
    case triggerError = "TRIGGER_ERROR"
    case authError = "AUTH_ERROR"
}

struct PluginError: Error, Equatable {
    let code: PluginErrorCode
    let message: String

    static func invalidArguments(_ message: String) -> PluginError {
        return PluginError(code: .invalidArguments, message: message)
    }

    var flutterError: FlutterError {
        return FlutterError(code: code.rawValue, message: message, details: nil)
    }
}

// MARK: - Argument access (never force-unwraps platform input)

struct Arguments {
    let map: [String: Any]

    init(_ map: [String: Any]) {
        self.map = map
    }

    /// Wraps `call.arguments`; anything that is not a String-keyed map is rejected.
    static func from(_ raw: Any?) throws -> Arguments {
        guard let map = raw as? [String: Any] else {
            throw PluginError.invalidArguments("Arguments must be a map.")
        }
        return Arguments(map)
    }

    func string(_ key: String) throws -> String {
        guard let value = map[key] as? String, !value.isEmpty else {
            throw PluginError.invalidArguments("Missing or invalid string argument '\(key)'.")
        }
        return value
    }

    /// A string that may be missing, `null`, or empty (all treated as nil).
    func optionalString(_ key: String) throws -> String? {
        guard let raw = map[key], !(raw is NSNull) else { return nil }
        guard let value = raw as? String else {
            throw PluginError.invalidArguments("Argument '\(key)' must be a string.")
        }
        return value.isEmpty ? nil : value
    }

    func bool(_ key: String, default defaultValue: Bool) throws -> Bool {
        guard let raw = map[key], !(raw is NSNull) else { return defaultValue }
        guard let value = raw as? Bool else {
            throw PluginError.invalidArguments("Argument '\(key)' must be a bool.")
        }
        return value
    }

    func int(_ key: String, default defaultValue: Int) throws -> Int {
        guard let raw = map[key], !(raw is NSNull) else { return defaultValue }
        guard let value = raw as? Int else {
            throw PluginError.invalidArguments("Argument '\(key)' must be an int.")
        }
        return value
    }
}

// MARK: - Options mapping (architecture.md section 4.1)

struct PusherOptionsConfig: Equatable {
    var cluster: String?
    var host: String?
    var wsPort: Int = 80
    var wssPort: Int = 443
    var useTLS: Bool = true
    var activityTimeoutMs: Int = 120_000
    var pongTimeoutMs: Int = 30_000
    var maxReconnectionAttempts: Int = 6
    var maxReconnectGapInSeconds: Int = 30
    var hasAuthorizer: Bool = false

    static func parse(_ raw: Any?) throws -> PusherOptionsConfig {
        guard let map = raw as? [String: Any] else {
            throw PluginError.invalidArguments("Missing or invalid 'options' map.")
        }
        let args = Arguments(map)
        var config = PusherOptionsConfig()
        config.cluster = try args.optionalString("cluster")
        config.host = try args.optionalString("host")
        config.wsPort = try args.int("wsPort", default: config.wsPort)
        config.wssPort = try args.int("wssPort", default: config.wssPort)
        config.useTLS = try args.bool("useTLS", default: config.useTLS)
        config.activityTimeoutMs = try args.int("activityTimeout", default: config.activityTimeoutMs)
        config.pongTimeoutMs = try args.int("pongTimeout", default: config.pongTimeoutMs)
        config.maxReconnectionAttempts = try args.int(
            "maxReconnectionAttempts", default: config.maxReconnectionAttempts)
        config.maxReconnectGapInSeconds = try args.int(
            "maxReconnectGapInSeconds", default: config.maxReconnectGapInSeconds)
        config.hasAuthorizer = try args.bool("hasAuthorizer", default: false)

        for (name, port) in [("wsPort", config.wsPort), ("wssPort", config.wssPort)] {
            guard (1...65535).contains(port) else {
                throw PluginError.invalidArguments("Option '\(name)' must be between 1 and 65535.")
            }
        }
        guard config.activityTimeoutMs > 0, config.pongTimeoutMs > 0 else {
            throw PluginError.invalidArguments("Timeouts must be positive.")
        }
        return config
    }

    /// Explicit `host` wins over `cluster`; otherwise `cluster`; otherwise the library default.
    var pusherHost: PusherHost {
        if let host = host { return .host(host) }
        if let cluster = cluster { return .cluster(cluster) }
        return .defaultHost
    }

    var port: Int {
        return useTLS ? wssPort : wsPort
    }

    var activityTimeout: TimeInterval {
        return TimeInterval(activityTimeoutMs) / 1000.0
    }

    var pongTimeout: TimeInterval {
        return TimeInterval(pongTimeoutMs) / 1000.0
    }

    func clientOptions(authorizer: Authorizer) -> PusherClientOptions {
        return PusherClientOptions(
            authMethod: .authorizer(authorizer: authorizer),
            host: pusherHost,
            port: port,
            useTLS: useTLS,
            activityTimeout: activityTimeout
        )
    }

    /// `Pusher(key:options:)` force-unwraps the socket URL, so reject inputs that cannot form one.
    func validateSocketURL(appKey: String) throws {
        let options = clientOptions(authorizer: NoopAuthorizer())
        let keyAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard appKey.rangeOfCharacter(from: keyAllowed.inverted) == nil else {
            throw PluginError(code: .initError, message: "appKey contains characters that are not valid in a URL.")
        }
        var components = URLComponents()
        components.scheme = options.useTLS ? "wss" : "ws"
        components.host = options.host
        components.port = options.port
        components.path = "/app/\(appKey)"
        guard components.url != nil, components.host == options.host else {
            throw PluginError(code: .initError, message: "Invalid host '\(options.host)'.")
        }
    }
}

private final class NoopAuthorizer: NSObject, Authorizer {
    func fetchAuthValue(socketID: String, channelName: String, completionHandler: @escaping (PusherAuth?) -> Void) {
        completionHandler(nil)
    }
}

// MARK: - Connection state (architecture.md section 4.3)

enum ConnectionStateMapper {
    static func normalize(_ state: ConnectionState) -> String {
        switch state {
        case .connecting: return "CONNECTING"
        case .connected: return "CONNECTED"
        case .disconnecting: return "DISCONNECTING"
        case .disconnected: return "DISCONNECTED"
        case .reconnecting: return "RECONNECTING"
        @unknown default: return "DISCONNECTED"
        }
    }
}

// MARK: - Channel kinds

enum ChannelKind: Equatable {
    case `public`
    case `private`
    case privateEncrypted
    case presence

    init(name: String) {
        if name.hasPrefix("presence-") {
            self = .presence
        } else if name.hasPrefix("private-encrypted-") {
            self = .privateEncrypted
        } else if name.hasPrefix("private-") {
            self = .private
        } else {
            self = .public
        }
    }

    /// Client events are only allowed on private (not encrypted) and presence channels.
    var supportsClientEvents: Bool {
        return self == .private || self == .presence
    }
}

// MARK: - Event payloads (architecture.md section 5)

enum EventPayloads {
    static func nullable(_ value: Any?) -> Any {
        return value ?? NSNull()
    }

    /// Serialises JSON-compatible values with `JSONSerialization` (sorted keys for stable output).
    static func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// `user_info` must be real JSON; anything JSON cannot represent becomes null.
    static func jsonSafe(_ value: Any?) -> Any {
        guard let value = value, !(value is NSNull) else { return NSNull() }
        if value is String || value is NSNumber { return value }
        if JSONSerialization.isValidJSONObject(value) { return value }
        return NSNull()
    }

    static func connectionStateChange(
        instanceId: String, current: String, previous: String, socketId: String?
    ) -> [String: Any] {
        return [
            "instanceId": instanceId,
            "type": "connectionStateChange",
            "currentState": current,
            "previousState": previous,
            "socketId": nullable(socketId),
        ]
    }

    static func connectionError(
        instanceId: String, message: String?, code: Int?, exception: String?
    ) -> [String: Any] {
        return [
            "instanceId": instanceId,
            "type": "connectionError",
            "message": nullable(message),
            "code": nullable(code.map { String($0) }),
            "exception": nullable(exception),
        ]
    }

    static func event(
        instanceId: String, channelName: String, eventName: String, data: String?, userId: String?
    ) -> [String: Any] {
        return [
            "instanceId": instanceId,
            "type": "event",
            "channelName": channelName,
            "eventName": eventName,
            "data": nullable(data),
            "userId": nullable(userId),
        ]
    }

    static func subscriptionError(
        instanceId: String, channelName: String, message: String, status: Int?
    ) -> [String: Any] {
        let body: [String: Any] = [
            "type": "AuthError",
            "error": message,
            "status": nullable(status),
        ]
        return event(
            instanceId: instanceId, channelName: channelName,
            eventName: "pusher:subscription_error", data: jsonString(body), userId: nil)
    }

    static func memberAdded(
        instanceId: String, channelName: String, userId: String, userInfo: Any?
    ) -> [String: Any] {
        let body: [String: Any] = ["user_id": userId, "user_info": jsonSafe(userInfo)]
        return event(
            instanceId: instanceId, channelName: channelName,
            eventName: "pusher:member_added", data: jsonString(body), userId: userId)
    }

    static func memberRemoved(instanceId: String, channelName: String, userId: String) -> [String: Any] {
        return event(
            instanceId: instanceId, channelName: channelName,
            eventName: "pusher:member_removed", data: jsonString(["user_id": userId]), userId: userId)
    }

    static func subscriptionCount(instanceId: String, channelName: String, count: Int) -> [String: Any] {
        return event(
            instanceId: instanceId, channelName: channelName,
            eventName: "pusher:subscription_count", data: jsonString(["subscription_count": count]),
            userId: nil)
    }

    static func decryptionError(
        instanceId: String, channelName: String, eventName: String, reason: String
    ) -> [String: Any] {
        return event(
            instanceId: instanceId, channelName: channelName,
            eventName: "pusher:decryption_error",
            data: jsonString(["event": eventName, "reason": reason]), userId: nil)
    }

    /// Forwards a library event. Events without a channel (connection level) are dropped.
    static func forwarded(
        instanceId: String, channelName: String?, eventName: String, data: String?, userId: String?
    ) -> [String: Any]? {
        guard let channelName = channelName else { return nil }
        return event(
            instanceId: instanceId, channelName: channelName, eventName: eventName,
            data: data, userId: userId)
    }

    static func forwarded(instanceId: String, event pusherEvent: PusherEvent) -> [String: Any]? {
        return forwarded(
            instanceId: instanceId, channelName: pusherEvent.channelName,
            eventName: pusherEvent.eventName, data: pusherEvent.data, userId: pusherEvent.userId)
    }
}

// MARK: - Authorization results (architecture.md section 4.2)

struct AuthFailure: Error, Equatable {
    let message: String
    let status: Int?
}

enum AuthResponse {
    /// Interprets whatever the Dart `authorize` call produced: a map, a `FlutterError`,
    /// `FlutterMethodNotImplemented`, or garbage.
    static func parse(_ raw: Any?, channelName: String) -> Result<PusherAuth, AuthFailure> {
        if let error = raw as? FlutterError {
            let details = error.details as? [String: Any]
            return .failure(AuthFailure(
                message: error.message ?? error.code,
                status: details?["status"] as? Int))
        }
        if let object = raw as AnyObject?, object === FlutterMethodNotImplemented {
            return .failure(AuthFailure(message: "Dart authorize handler is not implemented.", status: nil))
        }
        guard let map = raw as? [String: Any], let auth = map["auth"] as? String, !auth.isEmpty else {
            return .failure(AuthFailure(message: "Invalid authorize response from Dart.", status: nil))
        }
        let channelData = map["channel_data"] as? String
        let sharedSecret = map["shared_secret"] as? String
        if ChannelKind(name: channelName) == .presence && channelData == nil {
            return .failure(AuthFailure(
                message: "Presence channel authorization response is missing channel_data.", status: nil))
        }
        return .success(PusherAuth(auth: auth, channelData: channelData, sharedSecret: sharedSecret))
    }
}
