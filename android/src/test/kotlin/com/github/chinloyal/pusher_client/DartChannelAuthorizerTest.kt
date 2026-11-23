package com.github.chinloyal.pusher_client

import com.google.gson.JsonParser
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class DartChannelAuthorizerTest {
    private val direct: (Runnable) -> Unit = { it.run() }

    private fun authorizer(timeout: Long = 2000, invoker: DartInvoker) =
        DartChannelAuthorizer("inst", invoker, direct, timeout)

    @Test
    fun successReturnsJsonOmittingNulls() {
        var captured: Map<String, Any?>? = null
        val a = authorizer { args, cb ->
            captured = args
            cb.success(mapOf("auth" to "key:sig", "channel_data" to null, "shared_secret" to null))
        }
        val obj = JsonParser.parseString(a.authorize("private-x", "1.2")).asJsonObject
        assertEquals("key:sig", obj.get("auth").asString)
        assertEquals(1, obj.size())
        assertEquals(mapOf("instanceId" to "inst", "channelName" to "private-x", "socketId" to "1.2"), captured)
    }

    @Test
    fun successIncludesChannelDataAndSharedSecret() {
        val a = authorizer { _, cb ->
            cb.success(mapOf("auth" to "a", "channel_data" to "{\"user_id\":\"1\"}", "shared_secret" to "c2VjcmV0"))
        }
        val obj = JsonParser.parseString(a.authorize("presence-x", "1.2")).asJsonObject
        assertEquals("{\"user_id\":\"1\"}", obj.get("channel_data").asString)
        assertEquals("c2VjcmV0", obj.get("shared_secret").asString)
    }

    @Test
    fun dartErrorBecomesAuthorizationFailureWithStatus() {
        val a = authorizer { _, cb -> cb.error("AUTH_ERROR", "Forbidden", mapOf("status" to 403)) }
        val e = assertFailsWith<DartAuthorizationException> { a.authorize("private-x", "1.2") }
        assertEquals("Forbidden", e.message)
        assertEquals(403, e.status)
    }

    @Test
    fun dartErrorWithoutDetailsHasNoStatus() {
        val a = authorizer { _, cb -> cb.error("AUTH_ERROR", "bad", null) }
        assertEquals(null, assertFailsWith<DartAuthorizationException> { a.authorize("c", "s") }.status)
    }

    @Test
    fun notImplementedFails() {
        val a = authorizer { _, cb -> cb.notImplemented() }
        assertFailsWith<DartAuthorizationException> { a.authorize("c", "s") }
    }

    @Test
    fun missingAuthFails() {
        val a = authorizer { _, cb -> cb.success(mapOf("channel_data" to "x")) }
        assertFailsWith<DartAuthorizationException> { a.authorize("c", "s") }
        val b = authorizer { _, cb -> cb.success("nope") }
        assertFailsWith<DartAuthorizationException> { b.authorize("c", "s") }
    }

    @Test
    fun invokerThrowingFails() {
        val a = authorizer { _, _ -> throw IllegalStateException("detached") }
        val e = assertFailsWith<DartAuthorizationException> { a.authorize("c", "s") }
        assertTrue(e.message!!.contains("detached"))
    }

    @Test
    fun timesOutWhenDartNeverAnswers() {
        val a = authorizer(timeout = 50) { _, _ -> }
        val e = assertFailsWith<DartAuthorizationException> { a.authorize("c", "s") }
        assertTrue(e.message!!.contains("timed out"))
    }

    @Test
    fun lateAnswerAfterTimeoutIsIgnored() {
        var saved: DartAuthorizeCallback? = null
        val a = authorizer(timeout = 30) { _, cb -> saved = cb }
        assertFailsWith<DartAuthorizationException> { a.authorize("c", "s") }
        saved!!.success(mapOf("auth" to "late")) // must not throw
    }

    @Test
    fun blocksCallerUntilAnotherThreadAnswers() {
        var cb: DartAuthorizeCallback? = null
        val executor: (Runnable) -> Unit = { r -> thread { r.run() } }
        val a = DartChannelAuthorizer("inst", { _, c -> cb = c; thread { Thread.sleep(50); c.success(mapOf("auth" to "ok")) } }, executor, 2000)
        assertEquals("ok", JsonParser.parseString(a.authorize("c", "s")).asJsonObject.get("auth").asString)
    }
}
