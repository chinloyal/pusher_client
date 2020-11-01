package com.github.chinloyal.pusher_client.pusher.listeners

import android.os.Handler
import android.os.Looper
import com.github.chinloyal.pusher_client.core.utils.Constants
import com.github.chinloyal.pusher_client.pusher.PusherService.Companion.debugLog
import com.github.chinloyal.pusher_client.pusher.PusherService.Companion.eventSink
import com.pusher.client.channel.ChannelEventListener
import com.pusher.client.channel.PusherEvent
import org.json.JSONObject
import java.lang.Exception

open class FlutterBaseChannelEventListener: ChannelEventListener {
    private val eventStreamJson = JSONObject();

    override fun onEvent(event: PusherEvent) {
        Handler(Looper.getMainLooper()).post {
            try {
                val eventJson = JSONObject(mapOf(
                        "channelName" to event.channelName,
                        "eventName" to event.eventName,
                        "userId" to event.userId,
                        "data" to event.data
                ))

                eventStreamJson.put("pusherEvent", eventJson)

                eventSink?.success(eventStreamJson.toString())
                debugLog("""
                |[ON_EVENT] Channel: ${event.channelName}, EventName: ${event.eventName},
                |Data: ${event.data}, User Id: ${event.userId}
                """.trimMargin())
            } catch (e: Exception) {
                eventSink?.error("ON_EVENT_ERROR", e.message, e)
            }

        }
    }

    override fun onSubscriptionSucceeded(channelName: String) {
        this.onEvent(PusherEvent(mapOf(
                "event" to Constants.SUBSCRIPTION_SUCCEEDED.value,
                "channel" to channelName,
                "user_id" to null,
                "data" to null
        )))
        debugLog("[PUBLIC] Subscribed: $channelName")

    }
}