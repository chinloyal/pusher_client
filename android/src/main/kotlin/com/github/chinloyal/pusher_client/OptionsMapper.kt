package com.github.chinloyal.pusher_client

import com.pusher.client.ChannelAuthorizer
import com.pusher.client.PusherOptions

/** Maps the `options` map of the `init` call to [PusherOptions] (§4.1). */
internal object OptionsMapper {
    fun toPusherOptions(map: Map<*, *>, authorizer: ChannelAuthorizer? = null): PusherOptions {
        val host = optString(map, "host")?.takeIf { it.isNotEmpty() }
        val cluster = optString(map, "cluster")?.takeIf { it.isNotEmpty() }
        val options = PusherOptions()

        // Same rule as pusher-js: an explicit host wins, then cluster, then the library default.
        when {
            host != null -> options.setHost(host)
            cluster != null -> options.setCluster(cluster)
        }

        optInt(map, "wsPort")?.let { options.setWsPort(it) }
        optInt(map, "wssPort")?.let { options.setWssPort(it) }
        optBool(map, "useTLS")?.let { options.setUseTLS(it) }
        optLong(map, "activityTimeout")?.let { options.setActivityTimeout(it) }
        optLong(map, "pongTimeout")?.let { options.setPongTimeout(it) }
        optInt(map, "maxReconnectionAttempts")?.let { options.setMaxReconnectionAttempts(it) }
        optInt(map, "maxReconnectGapInSeconds")?.let { options.setMaxReconnectGapInSeconds(it) }
        if (authorizer != null) options.setChannelAuthorizer(authorizer)
        return options
    }

    private fun optString(map: Map<*, *>, key: String): String? {
        val v = map[key] ?: return null
        return v as? String ?: throw InvalidArgumentsException("options.$key must be a String")
    }

    private fun optBool(map: Map<*, *>, key: String): Boolean? {
        val v = map[key] ?: return null
        return v as? Boolean ?: throw InvalidArgumentsException("options.$key must be a bool")
    }

    private fun optLong(map: Map<*, *>, key: String): Long? {
        val v = map[key] ?: return null
        return (v as? Number)?.toLong() ?: throw InvalidArgumentsException("options.$key must be an int")
    }

    private fun optInt(map: Map<*, *>, key: String): Int? = optLong(map, key)?.toInt()
}
