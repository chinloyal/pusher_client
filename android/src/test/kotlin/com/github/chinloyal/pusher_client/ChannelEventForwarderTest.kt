package com.github.chinloyal.pusher_client

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.pusher.client.channel.PusherEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Servers such as laravel-websockets and soketi may send a channel event's `data` as a JSON
 * value instead of a JSON-encoded string. pusher-java-client 2.4.x serialises it to a string;
 * these tests pin that behaviour so a library upgrade cannot regress it silently.
 */
class ChannelEventForwarderTest {
    private fun forward(frame: String): Map<String, Any?> {
        val emitted = mutableListOf<Map<String, Any?>>()
        val forwarder = ChannelEventForwarder("i1", "my-channel", { emitted.add(it) })
        val obj: JsonObject = JsonParser.parseString(frame).asJsonObject
        forwarder.onEvent(PusherEvent(obj))
        return emitted.single()
    }

    @Test
    fun objectDataBecomesJsonString() {
        val m = forward("""{"event":"e","channel":"c","data":{"a":1,"b":{"c":"x"}}}""")
        assertEquals("event", m["type"])
        assertEquals("e", m["eventName"])
        assertEquals("c", m["channelName"])
        val data = m["data"] as String
        val parsed = JsonParser.parseString(data).asJsonObject
        assertEquals(1, parsed.get("a").asInt)
        assertEquals("x", parsed.getAsJsonObject("b").get("c").asString)
    }

    @Test
    fun arrayDataBecomesJsonString() {
        val m = forward("""{"event":"e","channel":"c","data":[1,"two"]}""")
        val parsed = JsonParser.parseString(m["data"] as String).asJsonArray
        assertEquals(2, parsed.size())
        assertEquals("two", parsed[1].asString)
    }

    @Test
    fun numberDataBecomesString() {
        val m = forward("""{"event":"e","channel":"c","data":42}""")
        assertEquals(42, JsonParser.parseString(m["data"] as String).asInt)
    }

    @Test
    fun stringDataIsPassedThrough() {
        val m = forward("""{"event":"e","channel":"c","data":"{\"a\":1}"}""")
        assertEquals("{\"a\":1}", m["data"])
    }

    @Test
    fun missingDataIsNull() {
        val m = forward("""{"event":"e","channel":"c"}""")
        assertNull(m["data"])
    }
}
