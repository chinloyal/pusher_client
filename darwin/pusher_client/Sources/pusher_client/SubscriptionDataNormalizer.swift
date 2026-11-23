import Foundation
import Network
import NWWebSocket
import PusherSwift

/// Works around servers that omit `data` from `pusher_internal:subscription_succeeded`.
///
/// The Pusher protocol always includes `"data"` (Pusher Channels sends `"{}"` for
/// public and private channels), but some compatible servers, e.g. soketi 1.x and
/// laravel-websockets, leave it out. PusherSwift 10.1 then drops the event
/// entirely, so `pusher:subscription_succeeded` never reaches the app on iOS/macOS
/// even though the channel is subscribed.
///
/// This object sits between the websocket and `PusherConnection`, adds
/// `"data":"{}"` to such messages and forwards every callback unchanged.
final class SubscriptionDataNormalizer: WebSocketConnectionDelegate {
    private weak var target: PusherConnection?

    init(target: PusherConnection) {
        self.target = target
    }

    /// Installs the normalizer on `connection`'s socket. The returned object must
    /// be retained by the caller (the socket only holds its delegate weakly).
    static func install(on connection: PusherConnection) -> SubscriptionDataNormalizer? {
        guard let socket = connection.socket else { return nil }
        let normalizer = SubscriptionDataNormalizer(target: connection)
        socket.delegate = normalizer
        return normalizer
    }

    /// Returns `message` with `"data":"{}"` added when it is a
    /// `pusher_internal:subscription_succeeded` event without data; otherwise
    /// returns `message` unchanged.
    static func normalize(_ message: String) -> String {
        guard message.contains("pusher_internal:subscription_succeeded"),
              let bytes = message.data(using: .utf8),
              var json = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              json["event"] as? String == "pusher_internal:subscription_succeeded"
        else {
            return message
        }
        if let data = json["data"], !(data is NSNull) {
            return message
        }
        json["data"] = "{}"
        guard let normalized = try? JSONSerialization.data(withJSONObject: json),
              let string = String(data: normalized, encoding: .utf8)
        else {
            return message
        }
        return string
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
        target?.webSocketDidReceiveMessage(connection: connection, string: SubscriptionDataNormalizer.normalize(string))
    }

    func webSocketDidReceiveMessage(connection: WebSocketConnection, data: Data) {
        target?.webSocketDidReceiveMessage(connection: connection, data: data)
    }
}
