//
//  PusherService.swift
//  pusher_client
//
//  Created by Romario Chinloy on 10/26/20.
//

import Flutter
import PusherSwiftWithEncryption

class PusherService: MChannel {
    static let CHANNEL_NAME = "com.github.chinloyal/pusher_client"
    static let EVENT_STREAM = "com.github.chinloyal/pusher_client_stream"
    static let LOG_TAG = "PusherClientPlugin"
    static let PRIVATE_PREFIX = "private-"
    static let PRIVATE_ENCRYPTED_PREFIX = "private-encrypted-"
    static let PRESENCE_PREFIX = "presence-"
    
    private var _pusherInstance: Pusher!
    private var bindedEvents = Dictionary<String, String>()
    
    struct Utils {
        static var enableLogging = true
        static func debugLog(msg: String) {
            if(enableLogging) {
                debugPrint("D/\(PusherService.LOG_TAG): \(msg)")
            }
        }
        static func errorLog(msg: String) {
            if(enableLogging) {
                debugPrint("E/\(PusherService.LOG_TAG): \(msg)")
            }
        }
    }
    
    func register(messenger: FlutterBinaryMessenger) {
        let methodChannel = FlutterMethodChannel(name: PusherService.CHANNEL_NAME, binaryMessenger: messenger)
        
        methodChannel.setMethodCallHandler { (_ call:FlutterMethodCall, result:@escaping FlutterResult) in
            switch call.method {
            case "init":
                self.`init`(call, result: result)
            case "connect":
                self.connect(result: result)
            case "disconnect":
                self.disconnect(result: result)
            case "getSocketId":
                self.getSocketId(result: result)
            case "subscribe":
                self.subscribe(call, result: result)
            case "unsubscribe":
                self.unsubscribe(call, result: result)
            case "bind":
                self.bind(call, result: result)
            case "unbind":
                self.unbind(call, result: result)
            case "trigger":
                self.trigger(call, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        let eventChannel = FlutterEventChannel(name: PusherService.EVENT_STREAM, binaryMessenger: messenger)
        
        eventChannel.setStreamHandler(StreamHandler.default)
    }
    
    func `init`(_ call:FlutterMethodCall, result:@escaping FlutterResult) {
        do {
            let json = call.arguments as! String
            let pusherArgs: PusherArgs = try JSONDecoder().decode(PusherArgs.self, from: json.data(using: .utf8)!)
            
            Utils.enableLogging = pusherArgs.initArgs.enableLogging
            
            if(_pusherInstance == nil) {
                let pusherOptions = PusherClientOptions(
                    authMethod: pusherArgs.pusherOptions.auth == nil ? .noMethod : AuthMethod.authRequestBuilder(authRequestBuilder: AuthRequestBuilder(pusherAuth: pusherArgs.pusherOptions.auth!)),
                    host: pusherArgs.pusherOptions.cluster != nil ? .cluster(pusherArgs.pusherOptions.cluster!) : .host(pusherArgs.pusherOptions.host),
                    port: pusherArgs.pusherOptions.encrypted ? pusherArgs.pusherOptions.wssPort : pusherArgs.pusherOptions.wsPort,
                    useTLS: pusherArgs.pusherOptions.encrypted,
                    activityTimeout: Double(pusherArgs.pusherOptions.activityTimeout) / 1000
                    
                )
                
                _pusherInstance = Pusher(key: pusherArgs.appKey, options: pusherOptions)
                _pusherInstance.connection.reconnectAttemptsMax = pusherArgs.pusherOptions.maxReconnectionAttempts
                _pusherInstance.connection.maxReconnectGapInSeconds = Double(pusherArgs.pusherOptions.maxReconnectGapInSeconds)
                _pusherInstance.connection.pongResponseTimeoutInterval = Double(pusherArgs.pusherOptions.pongTimeout) / 1000
                _pusherInstance.connection.delegate = ConnectionListener.default
                Utils.debugLog(msg: "Pusher initialized")
                
                result(nil)
            }
        } catch let err {
            Utils.errorLog(msg: err.localizedDescription)
            result(FlutterError(code: "INIT_ERROR", message: err.localizedDescription, details: err))
        }
        
    }
    
    func connect(result:@escaping FlutterResult) {
        _pusherInstance.connect()
        result(nil)
    }
    
    func disconnect(result:@escaping FlutterResult) {
        _pusherInstance.disconnect()
        Utils.debugLog(msg: "Disconnect")
        result(nil)
    }
    
    func getSocketId(result:@escaping FlutterResult) {
        result(_pusherInstance.connection.socketId)
    }
    
    func subscribe(_ call:FlutterMethodCall, result:@escaping FlutterResult) {
        let channelMap = call.arguments as! [String: String]
        let channelName: String = channelMap["channelName"]!
        var channel: PusherChannel
        
        if(!channelName.starts(with: PusherService.PRESENCE_PREFIX)) {
            channel = _pusherInstance.subscribe(channelName)
        } else {
            channel = _pusherInstance.subscribeToPresenceChannel(channelName: channelName)
            for pEvent in Constants.PresenceEvents.allCases {
                channel.bind(eventName: pEvent.rawValue, eventCallback: ChannelEventListener.default.onEvent)
            }
        }
        
        for pEvent in Constants.Events.allCases {
            channel.bind(eventName: pEvent.rawValue, eventCallback: ChannelEventListener.default.onEvent)
        }
        
        Utils.debugLog(msg: "Subscribed: \(channelName)")
        result(nil)
    }
    
    func unsubscribe(_ call:FlutterMethodCall, result:@escaping FlutterResult) {
        let channelMap = call.arguments as! [String: String]
        let channelName: String = channelMap["channelName"]!
        
        _pusherInstance.unsubscribe(channelName)
        Utils.debugLog(msg: "Unsubscribed: \(channelName)")
        
        result(nil)
    }
    
    /**
     * Note binding can happen before the channel has been subscribed to
     */
    func bind(_ call:FlutterMethodCall, result:@escaping FlutterResult) {
        let map = call.arguments as! [String: String]
        let channelName: String = map["channelName"]!
        let eventName: String = map["eventName"]!
        var channel: PusherChannel
        
        if(!channelName.starts(with: PusherService.PRESENCE_PREFIX)) {
            channel = _pusherInstance.connection.channels.find(name: channelName)!
            bindedEvents[channelName + eventName] = channel.bind(eventName: eventName, eventCallback: ChannelEventListener.default.onEvent)
        } else {
            channel = _pusherInstance.connection.channels.findPresence(name: channelName)!
            bindedEvents[channelName + eventName] = channel.bind(eventName: eventName, eventCallback: ChannelEventListener.default.onEvent)
        }
        
        Utils.debugLog(msg: "[BIND] \(eventName)")
        result(nil)
    }
    
    func unbind(_ call:FlutterMethodCall, result:@escaping FlutterResult) {
        let map = call.arguments as! [String: String]
        let channelName: String = map["channelName"]!
        let eventName: String = map["eventName"]!
        var channel: PusherChannel
        let callBackId = bindedEvents[channelName + eventName]
        
        if(callBackId != nil) {
            if(!channelName.starts(with: PusherService.PRESENCE_PREFIX)) {
                channel = _pusherInstance.connection.channels.find(name: channelName)!
                channel.unbind(eventName: eventName, callbackId: callBackId!)
            } else {
                channel = _pusherInstance.connection.channels.findPresence(name: channelName)!
                channel.unbind(eventName: eventName, callbackId: callBackId!)
            }
        }
        
        Utils.debugLog(msg: "[UNBIND] \(eventName)")
        result(nil)
    }
    
    func trigger(_ call:FlutterMethodCall, result:@escaping FlutterResult) {
        do {
            let json = call.arguments as! String
            let clientEvent: ClientEvent = try JSONDecoder().decode(ClientEvent.self, from: json.data(using: .utf8)!)
            let channelName = clientEvent.channelName
            let eventName = clientEvent.eventName
            let data: String = clientEvent.data ?? ""
            let errorMessage = "Trigger can only be called on private and presence channels."
            
            switch clientEvent.channelName {
            case _ where channelName.starts(with: PusherService.PRIVATE_ENCRYPTED_PREFIX):
                result(FlutterError(code: "TRIGGER_ERROR", message: errorMessage, details: nil))
            case _ where channelName.starts(with: PusherService.PRIVATE_PREFIX):
                let channel: PusherChannel = _pusherInstance.connection.channels.find(name: channelName)!
                channel.trigger(eventName: eventName, data: data)
            case _ where channelName.starts(with: PusherService.PRESENCE_PREFIX):
                let channel: PusherPresenceChannel = _pusherInstance.connection.channels.findPresence(name: channelName)!
                channel.trigger(eventName: eventName, data: data)
            default:
                result(FlutterError(code: "TRIGGER_ERROR", message: errorMessage, details: nil))
            }
            
            Utils.debugLog(msg: "[TRIGGER] \(eventName)")
            result(nil)
        } catch let err {
            Utils.errorLog(msg: err.localizedDescription)
            result(FlutterError(code: "TRIGGER_ERROR", message: err.localizedDescription, details: err))
        }
        
    }
}
