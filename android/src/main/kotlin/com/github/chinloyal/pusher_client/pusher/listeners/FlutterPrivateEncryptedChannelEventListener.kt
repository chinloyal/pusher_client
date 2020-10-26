package com.github.chinloyal.pusher_client.pusher.listeners

import com.github.chinloyal.pusher_client.pusher.PusherService
import com.github.chinloyal.pusher_client.pusher.PusherService.Companion.enableLogging
import com.github.chinloyal.pusher_client.pusher.PusherService.Companion.errorLog
import com.pusher.client.channel.PrivateEncryptedChannelEventListener
import java.lang.Exception

class FlutterPrivateEncryptedChannelEventListener: FlutterBaseChannelEventListener(), PrivateEncryptedChannelEventListener {
    companion object {
        val instance = FlutterPrivateEncryptedChannelEventListener()
    }

    override fun onDecryptionFailure(event: String, reason: String) {
        errorLog("[PRIVATE-ENCRYPTED] Reason: $reason, Event: $event")
    }

    override fun onAuthenticationFailure(message: String, e: Exception) {
        errorLog(message)
        if(enableLogging) e.printStackTrace()
    }

    override fun onSubscriptionSucceeded(channelName: String) {
        PusherService.debugLog("[PRIVATE-ENCRYPTED] Subscribed: $channelName")
    }
}