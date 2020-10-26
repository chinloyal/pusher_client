package com.github.chinloyal.pusher_client.pusher.listeners

import com.github.chinloyal.pusher_client.pusher.PusherService
import com.pusher.client.channel.PresenceChannelEventListener
import com.pusher.client.channel.User
import java.lang.Exception

class FlutterPresenceChannelEventListener: FlutterBaseChannelEventListener(), PresenceChannelEventListener {
    companion object {
        val instance = FlutterPresenceChannelEventListener()
    }

    override fun onUsersInformationReceived(channelName: String, users: MutableSet<User>) {
        TODO("Not yet implemented")
    }

    override fun userUnsubscribed(channelName: String, user: User) {
        TODO("Not yet implemented")
    }

    override fun userSubscribed(channelName: String, user: User) {
        TODO("Not yet implemented")
    }

    override fun onAuthenticationFailure(message: String, e: Exception) {
        TODO("Not yet implemented")
    }

    override fun onSubscriptionSucceeded(channelName: String) {
        PusherService.debugLog("[PRESENCE] Subscribed: $channelName")
    }
}