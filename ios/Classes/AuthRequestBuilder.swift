//
//  AuthRequestBuilder.swift
//  pusher_client
//
//  Created by Romario Chinloy on 10/27/20.
//

import PusherSwift

class AuthRequestBuilder: AuthRequestBuilderProtocol {
    let pusherAuth: PusherAuth
    
    init(pusherAuth: PusherAuth) {
        self.pusherAuth = pusherAuth
    }
    
    func requestFor(socketID: String, channelName: String) -> URLRequest? {
        PusherService.Utils.debugLog(msg: "Socket ID: \(socketID)")
        PusherService.Utils.debugLog(msg: "channelName: \(channelName)")
        PusherService.Utils.debugLog(msg: "URL: \(pusherAuth.endpoint)")
        
        var request = URLRequest(url: URL(string: pusherAuth.endpoint)!)
        request.httpMethod = "POST"
        do {
            let authRequest = AuthRequest(socket_id: socketID, channel_name: channelName)
            if(pusherAuth.headers.values.contains("application/json")) {
                request.httpBody = try JSONEncoder().encode(authRequest)
            } else {
                request.httpBody = authRequest.valueUrlEncoded!.data(using: String.Encoding.utf8)
            }
            
            pusherAuth.headers.forEach { (key: String, value: String) in
                request.addValue(value, forHTTPHeaderField: key)
            }
            
            return request
        } catch {
            return nil
        }
    }
}
