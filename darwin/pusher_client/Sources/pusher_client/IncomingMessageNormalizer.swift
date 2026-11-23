import Foundation
import Network
import NWWebSocket
import PusherSwift

/// Works around servers whose messages PusherSwift 10.1 cannot decode.
///
/// 1. `pusher_internal:subscription_succeeded` without `data`. The Pusher
///    protocol always includes `"data"` (Pusher Channels sends `"{}"` for public
///    and private channels), but some compatible servers, e.g. soketi 1.x and
///    laravel-websockets, leave it out. PusherSwift then drops the event, so
///    `pusher:subscription_succeeded` never reaches the app even though the
///    channel is subscribed. `"data":"{}"` is added.
/// 2. Channel events whose `data` is a JSON value (object, array, number, bool)
///    instead of a JSON-encoded string, and a numeric `user_id`. The protocol
///    says both are strings; laravel-websockets and soketi may send them as
///    JSON values. PusherSwift reads them with `as? String`, so the app would
///    receive `data: null`. `data` is replaced by its JSON encoding and
///    `user_id` by its string form, which is what Pusher Channels would send.
///    `pusher:error` messages are left alone.
///
/// This object sits between the websocket and `PusherConnection`, rewrites such
/// messages and forwards every callback unchanged. Messages that need no change
/// are forwarded byte for byte.
final class IncomingMessageNormalizer: WebSocketConnectionDelegate {
    private weak var target: PusherConnection?

    init(target: PusherConnection) {
        self.target = target
    }

    /// Installs the normalizer on `connection`'s socket. The returned object must
    /// be retained by the caller (the socket only holds its delegate weakly).
    static func install(on connection: PusherConnection) -> IncomingMessageNormalizer? {
        guard let socket = connection.socket else { return nil }
        let normalizer = IncomingMessageNormalizer(target: connection)
        socket.delegate = normalizer
        return normalizer
    }

    /// Returns `message` rewritten as described on the type, or `message`
    /// itself when nothing needs to change or it cannot be parsed.
    static func normalize(_ message: String) -> String {
        guard let bytes = message.data(using: .utf8),
              var json = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        else {
            return message
        }
        let event = json["event"] as? String
        var changed = false

        if event == "pusher_internal:subscription_succeeded" {
            if json["data"] == nil || json["data"] is NSNull {
                json["data"] = "{}"
                changed = true
            }
        }

        if json["channel"] is String, event != "pusher:error" {
            if let data = json["data"], !(data is String), !(data is NSNull),
               let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
               let string = String(data: encoded, encoding: .utf8) {
                json["data"] = string
                changed = true
            }
            if let number = json["user_id"] as? NSNumber,
               CFGetTypeID(number) != CFBooleanGetTypeID() {
                json["user_id"] = stringForm(of: number)
                changed = true
            }
        }

        guard changed,
              let normalized = try? JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes]),
              let string = String(data: normalized, encoding: .utf8)
        else {
            return message
        }
        return string
    }

    /// `42`, not `42.0`, for whole numbers.
    private static func stringForm(of number: NSNumber) -> String {
        let double = number.doubleValue
        if double == double.rounded(), abs(double) < 9.007199254740992e15 {
            return String(number.int64Value)
        }
        return number.stringValue
    }

    // MARK: - WebSocketConnectionDelegate (forwarding)

    func webSocketDidConnect(connection: WebSocketConnection) {
        target?.webSocketDidConnect(connection: connection)
    }

    func webSocketDidDisconnect(connection: WebSocketConnection,
                                closeCode: NWProtocolWebSocket.CloseCode,
                                reason: Data?) {
        target?.webSocketDidDisconnect(connection: connection, closeCode: closeCode, reason: reason)
    }

    func webSocketViabilityDidChange(connection: WebSocketConnection, isViable: Bool) {
        target?.webSocketViabilityDidChange(connection: connection, isViable: isViable)
    }

    func webSocketDidAttemptBetterPathMigration(result: Result<WebSocketConnection, NWError>) {
        target?.webSocketDidAttemptBetterPathMigration(result: result)
    }

    func webSocketDidReceiveError(connection: WebSocketConnection, error: NWError) {
        target?.webSocketDidReceiveError(connection: connection, error: error)
    }

    func webSocketDidReceivePong(connection: WebSocketConnection) {
        target?.webSocketDidReceivePong(connection: connection)
    }

    func webSocketDidReceiveMessage(connection: WebSocketConnection, string: String) {
        target?.webSocketDidReceiveMessage(connection: connection, string: IncomingMessageNormalizer.normalize(string))
    }

    func webSocketDidReceiveMessage(connection: WebSocketConnection, data: Data) {
        target?.webSocketDidReceiveMessage(connection: connection, data: data)
    }
}
