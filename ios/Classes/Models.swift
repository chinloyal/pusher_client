//
//  Models.swift
//  pusher_client
//
//  Created by Romario Chinloy on 10/27/20.
//

struct PusherArgs: Codable {
    var appKey: String
    var pusherOptions: PusherOptions
    var initArgs: InitArgs
}

struct PusherOptions: Codable {
    var auth: PusherAuth?
    var cluster: String?
    var host: String
    var encrypted: Bool
    var activityTimeout: Int
    var pongTimeout: Int
    var wsPort: Int
    var wssPort: Int
    var maxReconnectionAttempts: Int
    var maxReconnectGapInSeconds: Int
}

struct PusherAuth: Codable {
    var endpoint: String
    var headers: [String: String]
}

struct InitArgs: Codable {
    var enableLogging: Bool
}

struct AuthRequest: Codable {
    var socket_id: String
    var channel_name: String
    var valueUrlEncoded: String?
    
    init(socket_id: String, channel_name: String) {
        self.socket_id = socket_id
        self.channel_name = channel_name
        self.valueUrlEncoded = "socket_id=\(socket_id)&channel_name=\(channel_name)"
    }
    
    private enum CodingKeys: String, CodingKey {
        case socket_id, channel_name
    }
}

struct EventStreamResult: Codable {
    var connectionStateChange: ConnectionStateChange?
    var connectionError: ConnectionError?
    var pusherEvent: Event?
    init(connectionStateChange: ConnectionStateChange) {
        self.connectionStateChange = connectionStateChange
    }
    
    init(connectionError: ConnectionError) {
        self.connectionError = connectionError
    }
    
    init(pusherEvent: Event) {
        self.pusherEvent = pusherEvent
    }
}

struct ConnectionStateChange: Codable {
    var currentState: String
    var previousState: String
    
    init(currentState: String, previousState: String) {
        self.currentState = currentState
        self.previousState = previousState
    }
}

struct ConnectionError: Codable {
    var message: String
    var code: String
    var exception: String
    
    init(message: String, code: String, exception: String) {
        self.message = message
        self.code = code
        self.exception = exception
    }
}

struct Event: Codable {
    var eventName: String
    var channelName: String?
    var userId: String?;
    var data: String?;
}

struct ClientEvent: Codable {
    var eventName: String
    var channelName: String
    var data: String?;
}
