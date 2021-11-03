//
//  ChannelEventListener.swift
//  pusher_client
//
//  Created by Romario Chinloy on 10/31/20.
//
import Foundation
import PusherSwiftWithEncryption

class ChannelEventListener {
    static let `default`: ChannelEventListener = ChannelEventListener()

    private init(){}

    func onEvent(event: PusherEvent) -> Void {
        let pusherEvent = Event(eventName: event.eventName, channelName: event.channelName, userId: event.userId, data: event.data)
        streamEvent(event: pusherEvent, logTag: "ON_EVENT")
    }

    func onMemberAdded(channelName: String, member: PusherPresenceChannelMember) -> Void {
        let eventName = Constants.PresenceEvents.memberAdded.rawValue
        let pusherEvent = Event(eventName: eventName, channelName: channelName, userId: member.userId, data: "\(member.userInfo ?? "")")
        streamEvent(event: pusherEvent, logTag: "ON_MEMBER_ADDED")
    }

    func onMemberRemoved(channelName: String, member: PusherPresenceChannelMember) -> Void {
        let eventName = Constants.PresenceEvents.memberRemoved.rawValue
        let pusherEvent = Event(eventName: eventName, channelName: channelName, userId: member.userId, data: "\(member.userInfo ?? "")")
        streamEvent(event: pusherEvent, logTag: "ON_MEMBER_REMOVED")
    }

    private func streamEvent(event: Event, logTag: String) {
        do {
            let data = try JSONEncoder().encode(EventStreamResult(pusherEvent: event))
            StreamHandler.Utils.eventSink!(String(data: data, encoding: .utf8))

            PusherService.Utils.debugLog(msg: "[\(logTag)] Channel: \(event.channelName ?? ""), EventName: \(event.eventName), User Id: \(event.userId ?? ""), Data: \(event.data ?? "")")
        } catch let err {
            StreamHandler.Utils.eventSink!(FlutterError(code: "\(logTag)_ERROR", message: err.localizedDescription, details: err))
        }
    }
}