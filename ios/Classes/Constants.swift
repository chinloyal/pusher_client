//
//  Constants.swift
//  pusher_client
//
//  Created by Romario Chinloy on 10/31/20.
//

import Foundation

public enum Constants {
    enum Events: String, CaseIterable {
        case connectionEstablished = "pusher:connection_established"
        case error = "pusher:error"
        case subscribe = "pusher:subscribe"
        case unsubscribe = "pusher:unsubscribe"
        case subscriptionError = "pusher:subscription_error"
        case subscriptionSucceeded = "pusher:subscription_succeeded"
    }
    
    enum PresenceEvents: String, CaseIterable {
        case memberAdded = "pusher:member_added"
        case memberRemoved = "pusher:member_removed"
    }
}
