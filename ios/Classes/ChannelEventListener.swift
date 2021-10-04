//
//  ChannelEventListener.swift
//  pusher_client
//
//  Created by Romario Chinloy on 10/31/20.
//

import Foundation
import PusherSwift

class ChannelEventListener {
    static let `default`: ChannelEventListener = ChannelEventListener()
    
    private init(){}
    
    func onEvent(event: PusherEvent) -> Void {
        let pusherEvent = Event(eventName: event.eventName, channelName: event.channelName, userId: event.userId, data: event.data)
        
        do {
            let data = try JSONEncoder().encode(EventStreamResult(pusherEvent: pusherEvent))
            StreamHandler.Utils.eventSink!(String(data: data, encoding: .utf8))
            
            PusherService.Utils.debugLog(msg: "[ON_EVENT] Channel: \(event.channelName ?? ""), EventName: \(event.eventName), Data: \(event.data ?? ""), User Id: \(event.userId ?? "")")
        } catch let err {
            StreamHandler.Utils.eventSink!(FlutterError(code: "ON_EVENT_ERROR", message: err.localizedDescription, details: err))
        }
    }
}
