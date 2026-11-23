package com.github.chinloyal.pusher_client

import com.google.gson.GsonBuilder
import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonNull
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.JsonPrimitive
import com.pusher.client.channel.User
import com.pusher.client.connection.ConnectionState

/** Pure builders for the native -> Dart event maps (§5). */
internal object EventBuilder {
    private val gson = GsonBuilder().serializeNulls().disableHtmlEscaping().create()

    fun connectionStateChange(
        instanceId: String,
        current: ConnectionState?,
        previous: ConnectionState?,
        socketId: String?,
    ): Map<String, Any?> = mapOf(
        "instanceId" to instanceId,
        "type" to "connectionStateChange",
        "currentState" to ConnectionStates.normalize(current),
        "previousState" to ConnectionStates.normalize(previous),
        "socketId" to socketId,
    )

    fun connectionError(instanceId: String, message: String?, code: String?, exception: String?): Map<String, Any?> =
        mapOf(
            "instanceId" to instanceId,
            "type" to "connectionError",
            "message" to message,
            "code" to code,
            "exception" to exception,
        )

    fun channelEvent(
        instanceId: String,
        channelName: String,
        eventName: String?,
        data: String?,
        userId: String? = null,
    ): Map<String, Any?> = mapOf(
        "instanceId" to instanceId,
        "type" to "event",
        "channelName" to channelName,
        "eventName" to eventName,
        "data" to data,
        "userId" to userId,
    )

    /** `users == null` means a non-presence channel. */
    fun subscriptionSucceeded(instanceId: String, channelName: String, users: Collection<User>?): Map<String, Any?> =
        channelEvent(instanceId, channelName, "pusher:subscription_succeeded", presenceData(users))

    fun subscriptionError(instanceId: String, channelName: String, message: String?, status: Int?): Map<String, Any?> {
        val obj = JsonObject()
        obj.addProperty("type", "AuthError")
        obj.addProperty("error", message)
        obj.addProperty("status", status)
        return channelEvent(instanceId, channelName, "pusher:subscription_error", gson.toJson(obj))
    }

    fun memberAdded(instanceId: String, channelName: String, user: User): Map<String, Any?> {
        val obj = JsonObject()
        obj.addProperty("user_id", user.id)
        obj.add("user_info", infoElement(user.info))
        return channelEvent(instanceId, channelName, "pusher:member_added", gson.toJson(obj), user.id)
    }

    fun memberRemoved(instanceId: String, channelName: String, user: User): Map<String, Any?> {
        val obj = JsonObject()
        obj.addProperty("user_id", user.id)
        return channelEvent(instanceId, channelName, "pusher:member_removed", gson.toJson(obj), user.id)
    }

    fun subscriptionCount(instanceId: String, channelName: String, count: Int): Map<String, Any?> {
        val obj = JsonObject()
        obj.addProperty("subscription_count", count)
        return channelEvent(instanceId, channelName, "pusher:subscription_count", gson.toJson(obj))
    }

    fun decryptionError(instanceId: String, channelName: String, event: String?, reason: String?): Map<String, Any?> {
        val obj = JsonObject()
        obj.addProperty("event", event)
        obj.addProperty("reason", reason)
        return channelEvent(instanceId, channelName, "pusher:decryption_error", gson.toJson(obj))
    }

    /** `{"presence":{"count":N,"ids":[...],"hash":{"<id>":<info or null>}}}`, or `{}` when [users] is null. */
    fun presenceData(users: Collection<User>?): String {
        if (users == null) return "{}"
        val ids = JsonArray()
        val hash = JsonObject()
        for (user in users) {
            ids.add(user.id)
            hash.add(user.id, infoElement(user.info))
        }
        val presence = JsonObject()
        presence.addProperty("count", users.size)
        presence.add("ids", ids)
        presence.add("hash", hash)
        val root = JsonObject()
        root.add("presence", presence)
        return gson.toJson(root)
    }

    /** Parses a user_info JSON string into real JSON; falls back to the raw string if it is not valid JSON. */
    private fun infoElement(info: String?): JsonElement {
        if (info == null) return JsonNull.INSTANCE
        return try {
            JsonParser.parseString(info)
        } catch (e: Exception) {
            JsonPrimitive(info)
        }
    }
}
