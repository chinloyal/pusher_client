package com.github.chinloyal.pusher_client

import com.google.gson.JsonParser
import com.pusher.client.channel.User
import com.pusher.client.connection.ConnectionState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EventBuilderTest {
    private fun json(s: Any?) = JsonParser.parseString(s as String).asJsonObject

    @Test
    fun connectionStateChangeMap() {
        val m = EventBuilder.connectionStateChange("i1", ConnectionState.CONNECTED, ConnectionState.CONNECTING, "1.2")
        assertEquals(
            mapOf(
                "instanceId" to "i1", "type" to "connectionStateChange", "currentState" to "CONNECTED",
                "previousState" to "CONNECTING", "socketId" to "1.2",
            ),
            m,
        )
    }

    @Test
    fun connectionErrorMap() {
        val m = EventBuilder.connectionError("i1", "boom", "4001", "java.lang.Exception: x")
        assertEquals("connectionError", m["type"])
        assertEquals("4001", m["code"])
        assertEquals("boom", m["message"])
        assertEquals("java.lang.Exception: x", m["exception"])
    }

    @Test
    fun channelEventMap() {
        val m = EventBuilder.channelEvent("i1", "c", "e", "{\"a\":1}", "u1")
        assertEquals("event", m["type"])
        assertEquals("c", m["channelName"])
        assertEquals("e", m["eventName"])
        assertEquals("{\"a\":1}", m["data"])
        assertEquals("u1", m["userId"])
    }

    @Test
    fun publicSubscriptionSucceededIsEmptyObject() {
        val m = EventBuilder.subscriptionSucceeded("i1", "c", null)
        assertEquals("pusher:subscription_succeeded", m["eventName"])
        assertEquals("{}", m["data"])
    }

    @Test
    fun presenceSubscriptionSucceededShape() {
        val users = linkedSetOf(
            User("1", "{\"name\":\"A\",\"n\":[1,2]}"),
            User("2", null),
            User("3", "\"plain\""),
        )
        val data = json(EventBuilder.subscriptionSucceeded("i1", "presence-x", users)["data"])
        val presence = data.getAsJsonObject("presence")
        assertEquals(3, presence.get("count").asInt)
        assertEquals(listOf("1", "2", "3"), presence.getAsJsonArray("ids").map { it.asString })
        val hash = presence.getAsJsonObject("hash")
        assertEquals("A", hash.getAsJsonObject("1").get("name").asString)
        assertEquals(2, hash.getAsJsonObject("1").getAsJsonArray("n").size())
        assertTrue(hash.get("2").isJsonNull)
        assertEquals("plain", hash.get("3").asString)
    }

    @Test
    fun presenceWithNoUsers() {
        val presence = json(EventBuilder.presenceData(emptySet())).getAsJsonObject("presence")
        assertEquals(0, presence.get("count").asInt)
        assertEquals(0, presence.getAsJsonArray("ids").size())
        assertEquals(0, presence.getAsJsonObject("hash").size())
    }

    @Test
    fun memberAdded() {
        val m = EventBuilder.memberAdded("i1", "presence-x", User("7", "{\"k\":\"v\"}"))
        assertEquals("pusher:member_added", m["eventName"])
        assertEquals("7", m["userId"])
        val d = json(m["data"])
        assertEquals("7", d.get("user_id").asString)
        assertEquals("v", d.getAsJsonObject("user_info").get("k").asString)
    }

    @Test
    fun memberAddedWithoutInfoHasNullInfo() {
        val d = json(EventBuilder.memberAdded("i1", "presence-x", User("7", null))["data"])
        assertTrue(d.has("user_info"))
        assertTrue(d.get("user_info").isJsonNull)
    }

    @Test
    fun memberRemoved() {
        val m = EventBuilder.memberRemoved("i1", "presence-x", User("7", "{}"))
        assertEquals("pusher:member_removed", m["eventName"])
        assertEquals("7", m["userId"])
        val d = json(m["data"])
        assertEquals("7", d.get("user_id").asString)
        assertEquals(1, d.size())
    }

    @Test
    fun subscriptionCount() {
        val m = EventBuilder.subscriptionCount("i1", "c", 12)
        assertEquals("pusher:subscription_count", m["eventName"])
        assertEquals(12, json(m["data"]).get("subscription_count").asInt)
    }

    @Test
    fun decryptionError() {
        val m = EventBuilder.decryptionError("i1", "private-encrypted-x", "evt", "bad mac")
        assertEquals("pusher:decryption_error", m["eventName"])
        val d = json(m["data"])
        assertEquals("evt", d.get("event").asString)
        assertEquals("bad mac", d.get("reason").asString)
    }

    @Test
    fun subscriptionErrorWithStatus() {
        val m = EventBuilder.subscriptionError("i1", "private-x", "Forbidden", 403)
        assertEquals("pusher:subscription_error", m["eventName"])
        val d = json(m["data"])
        assertEquals("AuthError", d.get("type").asString)
        assertEquals("Forbidden", d.get("error").asString)
        assertEquals(403, d.get("status").asInt)
    }

    @Test
    fun subscriptionErrorWithoutStatusHasNullStatus() {
        val d = json(EventBuilder.subscriptionError("i1", "private-x", "nope", null)["data"])
        assertTrue(d.has("status"))
        assertTrue(d.get("status").isJsonNull)
        assertNull(EventBuilder.subscriptionError("i1", "c", "m", null)["userId"])
    }
}
