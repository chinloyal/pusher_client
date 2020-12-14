package com.github.chinloyal.pusher_client.pusher.listeners

import android.os.Handler
import android.os.Looper
import com.github.chinloyal.pusher_client.pusher.PusherService
import com.github.chinloyal.pusher_client.pusher.PusherService.Companion.debugLog
import com.github.chinloyal.pusher_client.pusher.PusherService.Companion.enableLogging
import com.github.chinloyal.pusher_client.pusher.PusherService.Companion.errorLog
import com.pusher.client.connection.ConnectionEventListener
import com.pusher.client.connection.ConnectionStateChange
import org.json.JSONObject
import java.lang.Exception

class ConnectionListener: ConnectionEventListener {
    val eventStreamJson = JSONObject();

    override fun onConnectionStateChange(change: ConnectionStateChange) {
        Handler(Looper.getMainLooper()).post {
            try {
                val connectionStateChange = JSONObject(mapOf(
                        "currentState" to change.currentState.toString(),
                        "previousState" to change.previousState.toString()
                ))

                debugLog("[${change.currentState.toString()}]")

                eventStreamJson.put("connectionStateChange", connectionStateChange)

                PusherService.eventSink?.success(eventStreamJson.toString())
            } catch (e: Exception) {
                e.message?.let { errorLog(it) }
                if (enableLogging) {
                    e.printStackTrace()
                }
            }
        }
    }

    override fun onError(message: String, code: String?, ex: Exception?) {
        Handler(Looper.getMainLooper()).post {
            try {
                val connectionError = JSONObject(mapOf(
                        "message" to message,
                        "code" to code,
                        "exception" to ex?.message
                ))

                debugLog("[ON_ERROR]: message: $message, code: $code")

                eventStreamJson.put("connectionError", connectionError)
                PusherService.eventSink?.success(eventStreamJson.toString())
            } catch (e: Exception) {
                e.message?.let { errorLog(it) }
                if (PusherService.enableLogging) {
                    e.printStackTrace()
                }
            }
        }
    }
}
