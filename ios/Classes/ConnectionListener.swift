//
//  ConnectionListener.swift
//  pusher_client
//
//  Created by Romario Chinloy on 10/27/20.
//

import PusherSwift

class ConnectionListener: PusherDelegate {
    static let `default`: ConnectionListener = ConnectionListener()
    
    private init(){}
    
    func changedConnectionState(from old: ConnectionState, to new: ConnectionState) {
        do {
            let connectionStateChange = ConnectionStateChange(currentState: new.stringValue(), previousState: old.stringValue())
            PusherService.Utils.debugLog(msg: "[\(new.stringValue())]")
            let data = try JSONEncoder().encode(EventStreamResult(connectionStateChange: connectionStateChange))
            
            StreamHandler.Utils.eventSink!(String(data: data, encoding: .utf8))
            
        } catch let err {
            PusherService.Utils.errorLog(msg: err.localizedDescription)
        }
       
    }
    
    func receivedError(error: PusherError) {
        do {
            let connectionError = ConnectionError(message: error.message, code: String(describing: error.code), exception: error.description)
            
            PusherService.Utils.debugLog(msg: "[ON_ERROR]: message: \(error.message), code: \(String(describing: error.code))")
            let data = try JSONEncoder().encode(EventStreamResult(connectionError: connectionError))
            StreamHandler.Utils.eventSink!(String(data: data, encoding: .utf8))
        } catch let err {
            PusherService.Utils.errorLog(msg: err.localizedDescription)
        }
        
    }
    
//    func debugLog(message: String) {
//        PusherService.Utils.debugLog(msg: message)
//    }
}
