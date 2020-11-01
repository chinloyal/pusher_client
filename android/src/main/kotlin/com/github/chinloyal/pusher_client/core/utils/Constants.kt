package com.github.chinloyal.pusher_client.core.utils

enum class Constants(val value: String) {
    CONNECTION_ESTABLISHED("pusher:connection_established"),
    ERROR("pusher:error"),
    SUBSCRIBE("pusher:subscribe"),
    UNSUBSCRIBE("pusher:unsubscribe"),
    SUBSCRIPTION_ERROR("pusher:subscription_error"),
    SUBSCRIPTION_SUCCEEDED("pusher:subscription_succeeded"),
    MEMBER_ADDED("pusher:member_added"),
    MEMBER_REMOVED("pusher:member_removed"),
}