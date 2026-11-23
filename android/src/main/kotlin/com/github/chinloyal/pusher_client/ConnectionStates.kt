package com.github.chinloyal.pusher_client

import com.pusher.client.connection.ConnectionState

/** Normalises pusher-java connection states to the protocol strings (§4.3). */
internal object ConnectionStates {
    fun normalize(state: ConnectionState?): String = when (state) {
        ConnectionState.CONNECTING -> "CONNECTING"
        ConnectionState.CONNECTED -> "CONNECTED"
        ConnectionState.DISCONNECTING -> "DISCONNECTING"
        ConnectionState.DISCONNECTED -> "DISCONNECTED"
        ConnectionState.RECONNECTING -> "RECONNECTING"
        // ALL is only a binding wildcard and null should never happen.
        ConnectionState.ALL, null -> "DISCONNECTED"
    }
}
