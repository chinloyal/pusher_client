package com.github.chinloyal.pusher_client

import com.google.gson.GsonBuilder
import com.google.gson.JsonObject
import com.pusher.client.AuthorizationFailureException
import com.pusher.client.ChannelAuthorizer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Callback for the Dart `authorize` invocation. */
interface DartAuthorizeCallback {
    fun success(result: Any?)
    fun error(code: String, message: String?, details: Any?)
    fun notImplemented()
}

/** Invokes the Dart `authorize` method. Always called on the main thread. */
fun interface DartInvoker {
    fun invokeAuthorize(arguments: Map<String, Any?>, callback: DartAuthorizeCallback)
}

/** Authorization failure carrying the optional HTTP status reported by Dart. */
class DartAuthorizationException(message: String, val status: Int? = null) : AuthorizationFailureException(message)

/**
 * pusher-java [ChannelAuthorizer] that delegates to Dart. It runs on the library's event thread, so it posts the
 * Dart call to the main thread and blocks *this* thread on a latch.
 */
internal class DartChannelAuthorizer(
    private val instanceId: String,
    private val invoker: DartInvoker,
    private val mainExecutor: (Runnable) -> Unit,
    private val timeoutMs: Long = Protocol.AUTHORIZE_TIMEOUT_MS,
    private val log: (String) -> Unit = {},
) : ChannelAuthorizer {

    private sealed class Outcome {
        class Ok(val json: String) : Outcome()
        class Fail(val message: String, val status: Int?) : Outcome()
    }

    override fun authorize(channelName: String, socketId: String): String {
        log("authorize request: channel=$channelName")
        val latch = CountDownLatch(1)
        val outcome = AtomicReference<Outcome?>(null)
        val done = { o: Outcome ->
            if (outcome.compareAndSet(null, o)) latch.countDown()
        }
        val args = mapOf<String, Any?>(
            "instanceId" to instanceId,
            "channelName" to channelName,
            "socketId" to socketId,
        )

        mainExecutor(Runnable {
            try {
                invoker.invokeAuthorize(args, object : DartAuthorizeCallback {
                    override fun success(result: Any?) = done(parse(result))

                    override fun error(code: String, message: String?, details: Any?) {
                        val status = ((details as? Map<*, *>)?.get("status") as? Number)?.toInt()
                        done(Outcome.Fail(message ?: "Authorization failed ($code)", status))
                    }

                    override fun notImplemented() =
                        done(Outcome.Fail("No authorizer is available on the Dart side", null))
                })
            } catch (e: Exception) {
                done(Outcome.Fail("Failed to invoke authorizer: ${e.message}", null))
            }
        })

        val finished = try {
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            throw DartAuthorizationException("Authorization interrupted")
        }
        if (!finished) {
            log("authorize failed: channel=$channelName timeout")
            throw DartAuthorizationException("Authorization timed out after ${timeoutMs / 1000.0} seconds")
        }
        return when (val o = outcome.get()) {
            is Outcome.Ok -> { log("authorize succeeded: channel=$channelName"); o.json }
            is Outcome.Fail -> { log("authorize failed: channel=$channelName status=${o.status} message=${o.message}"); throw DartAuthorizationException(o.message, o.status) }
            null -> throw DartAuthorizationException("Authorization failed")
        }
    }

    private fun parse(result: Any?): Outcome {
        val map = result as? Map<*, *> ?: return Outcome.Fail("Invalid authorization response", null)
        val auth = map["auth"] as? String ?: return Outcome.Fail("Authorization response is missing 'auth'", null)
        val obj = JsonObject()
        obj.addProperty("auth", auth)
        (map["channel_data"] as? String)?.let { obj.addProperty("channel_data", it) }
        (map["shared_secret"] as? String)?.let { obj.addProperty("shared_secret", it) }
        return Outcome.Ok(GSON.toJson(obj))
    }

    private companion object {
        val GSON = GsonBuilder().disableHtmlEscaping().create()
    }
}
