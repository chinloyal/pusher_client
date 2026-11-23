package com.github.chinloyal.pusher_client

import com.google.gson.JsonParser
import com.pusher.client.AuthorizationFailureException
import com.pusher.client.Pusher
import com.pusher.client.PusherOptions
import com.pusher.client.channel.Channel
import com.pusher.client.channel.ChannelEventListener
import com.pusher.client.channel.PresenceChannel
import com.pusher.client.channel.PresenceChannelEventListener
import com.pusher.client.channel.PrivateChannel
import com.pusher.client.channel.PrivateChannelEventListener
import com.pusher.client.channel.PrivateEncryptedChannel
import com.pusher.client.channel.PrivateEncryptedChannelEventListener
import com.pusher.client.channel.PusherEvent
import com.pusher.client.channel.SubscriptionEventListener
import com.pusher.client.channel.User
import com.pusher.client.connection.Connection
import com.pusher.client.connection.ConnectionEventListener
import com.pusher.client.connection.ConnectionState
import com.pusher.client.connection.ConnectionStateChange
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.times
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PusherMethodHandlerTest {
    private class Recorder : Reply {
        var count = 0
        var result: Any? = null
        var code: String? = null
        var message: String? = null
        var notImpl = false
        override fun success(result: Any?) { count++; this.result = result }
        override fun error(code: String, message: String?, details: Any?) { count++; this.code = code; this.message = message }
        override fun notImplemented() { count++; notImpl = true }
    }

    private val events = mutableListOf<Map<String, Any?>>()
    private val pusher: Pusher = mock()
    private val connection: Connection = mock()
    private var factoryCalls = 0
    private var lastOptions: PusherOptions? = null
    private var lastKey: String? = null
    private val logs = mutableListOf<String>()
    private var invoker = DartInvoker { _, cb -> cb.success(mapOf("auth" to "k:s")) }

    private lateinit var handler: PusherMethodHandler

    @BeforeTest
    fun setUp() {
        whenever(pusher.connection).thenReturn(connection)
        newHandler()
    }

    private fun newHandler() {
        handler = PusherMethodHandler(
            pusherFactory = { key, options -> factoryCalls++; lastKey = key; lastOptions = options; pusher },
            mainExecutor = { it.run() },
            emitter = EventEmitter { events.add(it) },
            dartInvoker = { args, cb -> invoker.invokeAuthorize(args, cb) },
            authorizeTimeoutMs = 500,
            logSink = { logs.add(it) },
        )
    }

    private fun call(method: String, args: Any? = null): Recorder {
        val r = Recorder()
        handler.handle(method, args, r)
        assertEquals(1, r.count, "method $method must reply exactly once")
        return r
    }

    private fun init(id: String = "i1"): Recorder = call(
        "init",
        mapOf(
            "instanceId" to id, "appKey" to "KEY", "enableLogging" to false,
            "options" to mapOf("host" to "h", "wsPort" to 1, "wssPort" to 2, "useTLS" to false),
        ),
    )

    private fun ok(r: Recorder) { assertNull(r.code, "unexpected error ${r.code}: ${r.message}") }

    // ---- init / lifecycle ------------------------------------------------

    @Test
    fun initCreatesPusherBindsConnectionListenerOnceAndDoesNotConnect() {
        ok(init())
        assertEquals("KEY", lastKey)
        assertTrue(lastOptions!!.buildUrl("KEY").startsWith("ws://h:1/app/KEY"))
        assertNotNull(lastOptions!!.channelAuthorizer)
        verify(connection, times(1)).bind(eq(ConnectionState.ALL), any())
        verify(pusher, never()).connect()
    }

    @Test
    fun connectAndDisconnectCallPusherWithoutListener() {
        init()
        ok(call("connect", mapOf("instanceId" to "i1")))
        verify(pusher).connect()
        verify(connection, times(1)).bind(eq(ConnectionState.ALL), any())
        ok(call("disconnect", mapOf("instanceId" to "i1")))
        verify(pusher).disconnect()
    }

    @Test
    fun initInvalidArguments() {
        assertEquals("INVALID_ARGUMENTS", call("init", null).code)
        assertEquals("INVALID_ARGUMENTS", call("init", mapOf("instanceId" to "i", "appKey" to "k")).code)
        assertEquals("INVALID_ARGUMENTS", call("init", mapOf("instanceId" to 1, "appKey" to "k", "options" to emptyMap<String, Any>())).code)
        assertEquals(
            "INVALID_ARGUMENTS",
            call("init", mapOf("instanceId" to "i", "appKey" to "k", "options" to mapOf("wsPort" to "x"))).code,
        )
        assertEquals(0, factoryCalls)
    }

    @Test
    fun initFactoryFailureReportsInitError() {
        handler = PusherMethodHandler({ _, _ -> throw IllegalStateException("nope") }, { it.run() }, { }, { _, _ -> })
        val r = init()
        assertEquals("INIT_ERROR", r.code)
    }

    @Test
    fun initTwiceReplacesAndDisconnectsOld() {
        init()
        init()
        assertEquals(2, factoryCalls)
        verify(pusher).disconnect()
    }

    @Test
    fun unknownInstanceIsNoInstance() {
        for (m in listOf("connect", "disconnect", "getSocketId")) {
            assertEquals("NO_INSTANCE", call(m, mapOf("instanceId" to "zzz")).code, m)
        }
        assertEquals("NO_INSTANCE", call("subscribe", mapOf("instanceId" to "zzz", "channelName" to "c")).code)
        assertEquals("NO_INSTANCE", call("unsubscribe", mapOf("instanceId" to "zzz", "channelName" to "c")).code)
        assertEquals(
            "NO_INSTANCE",
            call("trigger", mapOf("instanceId" to "zzz", "channelName" to "private-c", "eventName" to "client-e", "data" to "{}")).code,
        )
    }

    @Test
    fun missingOrWrongTypedArgumentsAreInvalid() {
        init()
        for (m in listOf("connect", "disconnect", "dispose", "getSocketId", "subscribe", "unsubscribe", "trigger")) {
            assertEquals("INVALID_ARGUMENTS", call(m, null).code, "$m null")
            assertEquals("INVALID_ARGUMENTS", call(m, emptyMap<String, Any>()).code, "$m empty")
            assertEquals("INVALID_ARGUMENTS", call(m, mapOf("instanceId" to 5)).code, "$m wrong type")
        }
        assertEquals("INVALID_ARGUMENTS", call("subscribe", mapOf("instanceId" to "i1")).code)
        assertEquals("INVALID_ARGUMENTS", call("subscribe", mapOf("instanceId" to "i1", "channelName" to 3)).code)
        assertEquals(
            "INVALID_ARGUMENTS",
            call("trigger", mapOf("instanceId" to "i1", "channelName" to "private-c", "eventName" to "client-e", "data" to mapOf("a" to 1))).code,
        )
    }

    @Test
    fun unknownMethodIsNotImplemented() {
        assertTrue(call("bogus").notImpl)
    }

    @Test
    fun disposeIsNoOpForUnknownAndReleasesKnown() {
        ok(call("dispose", mapOf("instanceId" to "ghost")))
        init()
        ok(call("dispose", mapOf("instanceId" to "i1")))
        verify(pusher).disconnect()
        assertEquals("NO_INSTANCE", call("connect", mapOf("instanceId" to "i1")).code)
        ok(call("dispose", mapOf("instanceId" to "i1")))
    }

    @Test
    fun disposeAllDropsEverythingAndAcceptsNullArguments() {
        init("a"); init("b")
        ok(call("disposeAll"))
        verify(pusher, times(2)).disconnect()
        assertEquals("NO_INSTANCE", call("connect", mapOf("instanceId" to "a")).code)
        assertEquals("NO_INSTANCE", call("connect", mapOf("instanceId" to "b")).code)
        ok(call("disposeAll", emptyMap<String, Any>()))
    }

    @Test
    fun getSocketId() {
        init()
        whenever(connection.socketId).thenReturn("12.34")
        assertEquals("12.34", call("getSocketId", mapOf("instanceId" to "i1")).result)
        whenever(connection.socketId).thenReturn(null)
        assertNull(call("getSocketId", mapOf("instanceId" to "i1")).result)
    }

    // ---- connection events -----------------------------------------------

    @Test
    fun connectionListenerEmitsNormalisedStateAndErrors() {
        init()
        val captor = argumentCaptor<ConnectionEventListener>()
        verify(connection).bind(eq(ConnectionState.ALL), captor.capture())
        whenever(connection.socketId).thenReturn("1.2")

        captor.firstValue.onConnectionStateChange(ConnectionStateChange(ConnectionState.CONNECTING, ConnectionState.CONNECTED))
        captor.firstValue.onConnectionStateChange(ConnectionStateChange(ConnectionState.CONNECTED, ConnectionState.DISCONNECTED))
        captor.firstValue.onError("bad", "4001", RuntimeException("x"))

        assertEquals("CONNECTED", events[0]["currentState"])
        assertEquals("CONNECTING", events[0]["previousState"])
        assertEquals("1.2", events[0]["socketId"])
        assertEquals("i1", events[0]["instanceId"])
        assertEquals("DISCONNECTED", events[1]["currentState"])
        assertNull(events[1]["socketId"])
        assertEquals("connectionError", events[2]["type"])
        assertEquals("4001", events[2]["code"])
    }

    @Test
    fun noEventsAfterDispose() {
        init()
        val captor = argumentCaptor<ConnectionEventListener>()
        verify(connection).bind(eq(ConnectionState.ALL), captor.capture())
        call("dispose", mapOf("instanceId" to "i1"))
        captor.firstValue.onError("late", null, null)
        assertTrue(events.isEmpty())
    }

    // ---- subscribe -------------------------------------------------------

    private fun subArgs(name: String) = mapOf("instanceId" to "i1", "channelName" to name)

    @Test
    fun subscribePublicUsesPlainSubscribeAndBindsGlobal() {
        init()
        val ch: Channel = mock()
        whenever(pusher.subscribe(eq("news"), any<ChannelEventListener>())).thenReturn(ch)
        ok(call("subscribe", subArgs("news")))
        verify(pusher).subscribe(eq("news"), any<ChannelEventListener>())
        verify(ch).bindGlobal(any())
    }

    @Test
    fun subscribePrivateUsesPrivate() {
        init()
        val ch: PrivateChannel = mock()
        whenever(pusher.subscribePrivate(eq("private-a"), any<PrivateChannelEventListener>())).thenReturn(ch)
        ok(call("subscribe", subArgs("private-a")))
        verify(pusher).subscribePrivate(eq("private-a"), any<PrivateChannelEventListener>())
        verify(ch).bindGlobal(any())
    }

    @Test
    fun subscribeEncryptedUsesEncrypted() {
        init()
        val ch: PrivateEncryptedChannel = mock()
        whenever(pusher.subscribePrivateEncrypted(eq("private-encrypted-a"), any<PrivateEncryptedChannelEventListener>())).thenReturn(ch)
        ok(call("subscribe", subArgs("private-encrypted-a")))
        verify(pusher).subscribePrivateEncrypted(eq("private-encrypted-a"), any<PrivateEncryptedChannelEventListener>())
        verify(pusher, never()).subscribePrivate(any(), any<PrivateChannelEventListener>())
    }

    @Test
    fun subscribePresenceUsesPresence() {
        init()
        val ch: PresenceChannel = mock()
        whenever(pusher.subscribePresence(eq("presence-a"), any<PresenceChannelEventListener>())).thenReturn(ch)
        ok(call("subscribe", subArgs("presence-a")))
        verify(pusher).subscribePresence(eq("presence-a"), any<PresenceChannelEventListener>())
    }

    @Test
    fun subscribeIsIdempotent() {
        init()
        whenever(pusher.subscribe(eq("news"), any<ChannelEventListener>())).thenReturn(mock<Channel>())
        call("subscribe", subArgs("news"))
        ok(call("subscribe", subArgs("news")))
        verify(pusher, times(1)).subscribe(eq("news"), any<ChannelEventListener>())
    }

    @Test
    fun subscribeFailureIsSubscribeError() {
        init()
        whenever(pusher.subscribe(eq("news"), any<ChannelEventListener>())).thenThrow(IllegalArgumentException("bad"))
        val r = call("subscribe", subArgs("news"))
        assertEquals("SUBSCRIBE_ERROR", r.code)
    }

    @Test
    fun unsubscribeRemovesAndIsIdempotent() {
        init()
        whenever(pusher.subscribe(eq("news"), any<ChannelEventListener>())).thenReturn(mock<Channel>())
        call("subscribe", subArgs("news"))
        ok(call("unsubscribe", subArgs("news")))
        ok(call("unsubscribe", subArgs("news")))
        verify(pusher, times(2)).unsubscribe("news")
        // can subscribe again afterwards
        call("subscribe", subArgs("news"))
        verify(pusher, times(2)).subscribe(eq("news"), any<ChannelEventListener>())
    }

    // ---- channel event forwarding -----------------------------------------

    @Test
    fun publicSubscriptionSucceededEmitsExactlyOnceWithEmptyData() {
        init()
        val listener = argumentCaptor<ChannelEventListener>()
        whenever(pusher.subscribe(eq("news"), listener.capture())).thenReturn(mock<Channel>())
        call("subscribe", subArgs("news"))
        listener.firstValue.onSubscriptionSucceeded("news")
        assertEquals(1, events.size)
        assertEquals("pusher:subscription_succeeded", events[0]["eventName"])
        assertEquals("{}", events[0]["data"])
        assertEquals("news", events[0]["channelName"])
    }

    @Test
    fun presenceEmitsSingleSucceededFromUsersAndMemberEvents() {
        init()
        val ch: PresenceChannel = mock()
        whenever(ch.users).thenReturn(linkedSetOf(User("1", "{\"n\":\"a\"}"), User("2", null)))
        val listener = argumentCaptor<PresenceChannelEventListener>()
        whenever(pusher.subscribePresence(eq("presence-r"), listener.capture())).thenReturn(ch)
        call("subscribe", subArgs("presence-r"))
        val l = listener.firstValue

        l.onSubscriptionSucceeded("presence-r")
        l.onUsersInformationReceived("presence-r", setOf(User("1", null)))
        assertEquals(1, events.size, "only one subscription_succeeded")
        val presence = JsonParser.parseString(events[0]["data"] as String).asJsonObject.getAsJsonObject("presence")
        assertEquals(2, presence.get("count").asInt)
        assertEquals("a", presence.getAsJsonObject("hash").getAsJsonObject("1").get("n").asString)

        l.userSubscribed("presence-r", User("3", "{}"))
        l.userUnsubscribed("presence-r", User("3", "{}"))
        assertEquals("pusher:member_added", events[1]["eventName"])
        assertEquals("pusher:member_removed", events[2]["eventName"])
        assertEquals("3", events[2]["userId"])
    }

    @Test
    fun authFailureEmitsSubscriptionErrorWithStatus() {
        init()
        val listener = argumentCaptor<PrivateChannelEventListener>()
        whenever(pusher.subscribePrivate(eq("private-a"), listener.capture())).thenReturn(mock<PrivateChannel>())
        call("subscribe", subArgs("private-a"))
        listener.firstValue.onAuthenticationFailure("Forbidden", DartAuthorizationException("Forbidden", 403))
        listener.firstValue.onAuthenticationFailure("other", AuthorizationFailureException("other"))

        val d0 = JsonParser.parseString(events[0]["data"] as String).asJsonObject
        assertEquals("pusher:subscription_error", events[0]["eventName"])
        assertEquals("Forbidden", d0.get("error").asString)
        assertEquals(403, d0.get("status").asInt)
        assertTrue(JsonParser.parseString(events[1]["data"] as String).asJsonObject.get("status").isJsonNull)
    }

    @Test
    fun decryptionFailureEmitsDecryptionError() {
        init()
        val listener = argumentCaptor<PrivateEncryptedChannelEventListener>()
        whenever(pusher.subscribePrivateEncrypted(eq("private-encrypted-a"), listener.capture())).thenReturn(mock<PrivateEncryptedChannel>())
        call("subscribe", subArgs("private-encrypted-a"))
        listener.firstValue.onDecryptionFailure("evt", "bad")
        assertEquals("pusher:decryption_error", events[0]["eventName"])
    }

    @Test
    fun globalListenerForwardsAppAndSubscriptionCountEvents() {
        init()
        val ch: Channel = mock()
        whenever(pusher.subscribe(eq("news"), any<ChannelEventListener>())).thenReturn(ch)
        call("subscribe", subArgs("news"))
        val global = argumentCaptor<SubscriptionEventListener>()
        verify(ch).bindGlobal(global.capture())

        global.firstValue.onEvent(PusherEvent("my-event", "news", "u9", "{\"a\":1}"))
        global.firstValue.onEvent(PusherEvent("pusher:subscription_count", "news", null, "{\"subscription_count\":4}"))
        assertEquals("my-event", events[0]["eventName"])
        assertEquals("{\"a\":1}", events[0]["data"])
        assertEquals("u9", events[0]["userId"])
        assertEquals("news", events[0]["channelName"])
        assertEquals("pusher:subscription_count", events[1]["eventName"])
        assertEquals("{\"subscription_count\":4}", events[1]["data"])
        assertNull(events[1]["userId"])
    }

    @Test
    fun authenticationFailureAllowsResubscribe() {
        init()
        val listener = argumentCaptor<PrivateChannelEventListener>()
        whenever(pusher.subscribePrivate(eq("private-a"), listener.capture())).thenReturn(mock<PrivateChannel>())
        call("subscribe", subArgs("private-a"))
        listener.firstValue.onAuthenticationFailure("Forbidden", DartAuthorizationException("Forbidden", 403))
        call("subscribe", subArgs("private-a"))
        verify(pusher, times(2)).subscribePrivate(eq("private-a"), any<PrivateChannelEventListener>())
    }

    // ---- trigger ---------------------------------------------------------

    private fun trig(name: String, event: String = "client-e") =
        call("trigger", mapOf("instanceId" to "i1", "channelName" to name, "eventName" to event, "data" to "{\"x\":1}"))

    @Test
    fun triggerOnPrivateAndPresenceSucceedsOnce() {
        init()
        val priv: PrivateChannel = mock()
        val pres: PresenceChannel = mock()
        whenever(pusher.subscribePrivate(eq("private-a"), any<PrivateChannelEventListener>())).thenReturn(priv)
        whenever(pusher.subscribePresence(eq("presence-a"), any<PresenceChannelEventListener>())).thenReturn(pres)
        call("subscribe", subArgs("private-a"))
        call("subscribe", subArgs("presence-a"))
        ok(trig("private-a"))
        ok(trig("presence-a"))
        verify(priv).trigger("client-e", "{\"x\":1}")
        verify(pres).trigger("client-e", "{\"x\":1}")
    }

    @Test
    fun triggerValidatesChannelType() {
        init()
        whenever(pusher.subscribe(eq("news"), any<ChannelEventListener>())).thenReturn(mock<Channel>())
        whenever(pusher.subscribePrivateEncrypted(eq("private-encrypted-a"), any<PrivateEncryptedChannelEventListener>()))
            .thenReturn(mock<PrivateEncryptedChannel>())
        call("subscribe", subArgs("news"))
        call("subscribe", subArgs("private-encrypted-a"))
        assertEquals("TRIGGER_ERROR", trig("news").code)
        assertEquals("TRIGGER_ERROR", trig("private-encrypted-a").code)
    }

    @Test
    fun triggerOnUnsubscribedChannelIsError() {
        init()
        assertEquals("TRIGGER_ERROR", trig("private-nope").code)
    }

    @Test
    fun triggerLibraryFailureIsRepliedOnceAsTriggerError() {
        init()
        val priv: PrivateChannel = mock()
        whenever(pusher.subscribePrivate(eq("private-a"), any<PrivateChannelEventListener>())).thenReturn(priv)
        whenever(priv.trigger(any(), any())).thenThrow(IllegalStateException("not subscribed"))
        call("subscribe", subArgs("private-a"))
        val r = trig("private-a")
        assertEquals("TRIGGER_ERROR", r.code)
        assertEquals("not subscribed", r.message)
    }

    // ---- authorizer wiring ----------------------------------------------

    @Test
    fun installedAuthorizerCallsDartInvoker() {
        var seen: Map<String, Any?>? = null
        invoker = DartInvoker { args, cb -> seen = args; cb.success(mapOf("auth" to "k:s")) }
        init()
        val json = lastOptions!!.channelAuthorizer.authorize("private-a", "1.2")
        assertEquals("k:s", JsonParser.parseString(json).asJsonObject.get("auth").asString)
        assertEquals(mapOf("instanceId" to "i1", "channelName" to "private-a", "socketId" to "1.2"), seen)
    }

    @Test
    fun installedAuthorizerTimesOut() {
        invoker = DartInvoker { _, _ -> }
        init()
        kotlin.test.assertFailsWith<AuthorizationFailureException> { lastOptions!!.channelAuthorizer.authorize("private-a", "1.2") }
    }

    // ---- logging ---------------------------------------------------------

    private fun initWithLogging(enabled: Boolean) = call(
        "init",
        mapOf("instanceId" to "i1", "appKey" to "KEY", "enableLogging" to enabled, "options" to mapOf("host" to "h")),
    )

    @Test
    fun loggingIsSilentWhenDisabled() {
        initWithLogging(false)
        val ch: PrivateChannel = mock()
        whenever(pusher.subscribePrivate(eq("private-a"), any<PrivateChannelEventListener>())).thenReturn(ch)
        call("connect", mapOf("instanceId" to "i1"))
        call("subscribe", subArgs("private-a"))
        lastOptions!!.channelAuthorizer.authorize("private-a", "1.2")
        call("dispose", mapOf("instanceId" to "i1"))
        assertTrue(logs.isEmpty(), logs.toString())
    }

    @Test
    fun loggingWritesLifecycleWhenEnabledWithoutSecrets() {
        invoker = DartInvoker { _, cb -> cb.success(mapOf("auth" to "SECRET-SIG", "channel_data" to "SECRET-DATA")) }
        initWithLogging(true)
        whenever(pusher.subscribePrivate(eq("private-a"), any<PrivateChannelEventListener>())).thenReturn(mock<PrivateChannel>())
        call("connect", mapOf("instanceId" to "i1"))
        call("subscribe", subArgs("private-a"))
        lastOptions!!.channelAuthorizer.authorize("private-a", "1.2")
        assertTrue(logs.any { it.contains("init") })
        assertTrue(logs.any { it.contains("connect") })
        assertTrue(logs.any { it.contains("subscribe private-a") })
        assertTrue(logs.any { it.contains("authorize succeeded") })
        assertTrue(logs.none { it.contains("SECRET") }, logs.toString())
    }
}
