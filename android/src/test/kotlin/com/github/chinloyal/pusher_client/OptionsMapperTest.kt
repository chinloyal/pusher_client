package com.github.chinloyal.pusher_client

import com.pusher.client.AuthorizationFailureException
import com.pusher.client.ChannelAuthorizer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertSame
import kotlin.test.assertTrue

class OptionsMapperTest {
    private fun base(vararg extra: Pair<String, Any?>): Map<String, Any?> = mapOf<String, Any?>(
        "cluster" to null, "host" to null, "wsPort" to 80, "wssPort" to 443, "useTLS" to true,
        "activityTimeout" to 120000, "pongTimeout" to 30000,
        "maxReconnectionAttempts" to 6, "maxReconnectGapInSeconds" to 30, "hasAuthorizer" to true,
    ) + extra

    private fun url(map: Map<String, Any?>) = OptionsMapper.toPusherOptions(map).buildUrl("KEY")

    @Test
    fun defaultsUseLibraryHost() {
        assertTrue(url(base()).startsWith("wss://ws.pusherapp.com:443/app/KEY"))
    }

    @Test
    fun clusterIsUsedWhenNoHost() {
        assertTrue(url(base("cluster" to "eu")).startsWith("wss://ws-eu.pusher.com:443/app/KEY"))
    }

    @Test
    fun hostWinsOverCluster() {
        val u = url(base("cluster" to "eu", "host" to "soketi.local", "wssPort" to 6002))
        assertTrue(u.startsWith("wss://soketi.local:6002/app/KEY"), u)
    }

    @Test
    fun portDependsOnUseTls() {
        val plain = url(base("host" to "h", "useTLS" to false, "wsPort" to 6001, "wssPort" to 6002))
        assertTrue(plain.startsWith("ws://h:6001/app/KEY"), plain)
        val tls = url(base("host" to "h", "useTLS" to true, "wsPort" to 6001, "wssPort" to 6002))
        assertTrue(tls.startsWith("wss://h:6002/app/KEY"), tls)
    }

    @Test
    fun emptyHostFallsBackToCluster() {
        assertTrue(url(base("host" to "", "cluster" to "ap1")).startsWith("wss://ws-ap1.pusher.com"))
    }

    @Test
    fun numericSettingsAreApplied() {
        val o = OptionsMapper.toPusherOptions(
            base("activityTimeout" to 5000L, "pongTimeout" to 7000, "maxReconnectionAttempts" to 2, "maxReconnectGapInSeconds" to 9)
        )
        assertEquals(5000L, o.activityTimeout)
        assertEquals(7000L, o.pongTimeout)
        assertEquals(2, o.maxReconnectionAttempts)
        assertEquals(9, o.maxReconnectGapInSeconds)
    }

    @Test
    fun authorizerIsInstalled() {
        val a = ChannelAuthorizer { _, _ -> throw AuthorizationFailureException("x") }
        assertSame(a, OptionsMapper.toPusherOptions(base(), a).channelAuthorizer)
    }

    @Test
    fun wrongTypesAreRejected() {
        assertFailsWith<InvalidArgumentsException> { OptionsMapper.toPusherOptions(base("wsPort" to "80")) }
        assertFailsWith<InvalidArgumentsException> { OptionsMapper.toPusherOptions(base("host" to 5)) }
        assertFailsWith<InvalidArgumentsException> { OptionsMapper.toPusherOptions(base("useTLS" to "yes")) }
    }
}
