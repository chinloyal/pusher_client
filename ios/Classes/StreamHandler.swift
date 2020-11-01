//
//  StreamHandler.swift
//  pusher_client
//
//  Created by Romario Chinloy on 10/29/20.
//

class StreamHandler: NSObject, FlutterStreamHandler {
    static let `default`: StreamHandler = StreamHandler()
    
    private override init(){}
    
    struct Utils {
        static var eventSink: FlutterEventSink?
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        Utils.eventSink = events
        PusherService.Utils.debugLog(msg: "Event stream listening...")
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        PusherService.Utils.debugLog(msg: "Event stream cancelled.")
        return nil
    }
    
    
}
