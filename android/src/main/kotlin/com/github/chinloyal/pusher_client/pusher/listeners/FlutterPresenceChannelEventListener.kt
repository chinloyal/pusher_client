package com.github.chinloyal.pusher_client.pusher.listeners

import com.github.chinloyal.pusher_client.core.utils.Constants
import com.github.chinloyal.pusher_client.pusher.PusherService
import com.pusher.client.channel.PresenceChannelEventListener
import com.pusher.client.channel.PusherEvent
import com.pusher.client.channel.User
import java.lang.Exception

class FlutterPresenceChannelEventListener: FlutterBaseChannelEventListener(), PresenceChannelEventListener {
    companion object {
        val instance = FlutterPresenceChannelEventListener()
    }

    override fun onUsersInformationReceived(channelName: String, users: MutableSet<User>) {
        this.onEvent(PusherEvent(mapOf(
                "event" to Constants.SUBSCRIPTION_SUCCEEDED.value,
                "channel" to channelName,
                "user_id" to null,
                "data" to users.toString()
        )))
    }

    override fun userUnsubscribed(channelName: String, user: User) {
        this.onEvent(PusherEvent(mapOf(
                "event" to Constants.MEMBER_REMOVED.value,
                "channel" to channelName,
                "user_id" to user.id,
                "data" to null
        )))
    }

    override fun userSubscribed(channelName: String, user: User) {
        this.onEvent(PusherEvent(mapOf(
                "event" to Constants.MEMBER_ADDED.value,
                "channel" to channelName,
                "user_id" to user.id,
                "data" to null
        )))
    }

    override fun onAuthenticationFailure(message: String, e: Exception) {
        PusherService.errorLog(message)
        if(PusherService.enableLogging) e.printStackTrace()
    }

    override fun onSubscriptionSucceeded(channelName: String) {
        PusherService.debugLog("[PRESENCE] Subscribed: $channelName")

        this.onEvent(PusherEvent(mapOf(
                "event" to Constants.SUBSCRIPTION_SUCCEEDED.value,
                "channel" to channelName,
                "user_id" to null,
                "data" to null
        )))
    }
}