package com.github.chinloyal.pusher_client

import com.pusher.client.connection.ConnectionState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

class ConnectionStatesTest {
    @Test
    fun mapsEveryConcreteState() {
        assertEquals("CONNECTING", ConnectionStates.normalize(ConnectionState.CONNECTING))
        assertEquals("CONNECTED", ConnectionStates.normalize(ConnectionState.CONNECTED))
        assertEquals("DISCONNECTING", ConnectionStates.normalize(ConnectionState.DISCONNECTING))
        assertEquals("DISCONNECTED", ConnectionStates.normalize(ConnectionState.DISCONNECTED))
        assertEquals("RECONNECTING", ConnectionStates.normalize(ConnectionState.RECONNECTING))
    }

    @Test
    fun neverReturnsAll() {
        assertNotEquals("ALL", ConnectionStates.normalize(ConnectionState.ALL))
        assertEquals("DISCONNECTED", ConnectionStates.normalize(null))
    }
}
