package com.github.chinloyal.pusher_client

import com.pusher.client.channel.Channel
import com.pusher.client.channel.PresenceChannel
import com.pusher.client.channel.PresenceChannelEventListener
import com.pusher.client.channel.PrivateEncryptedChannelEventListener
import com.pusher.client.channel.PusherEvent
import com.pusher.client.channel.User

/**
 * One per subscribed channel. Used both as the subscribe-time listener (lifecycle callbacks) and, via
 * `bindGlobal`, as the listener for every app / client / subscription_count event.
 * Callbacks arrive on the library's event thread; [emit] hops to the main thread.
 */
internal class ChannelEventForwarder(
    private val instanceId: String,
    private val channelName: String,
    private val emit: (Map<String, Any?>) -> Unit,
    /** Called when the library drops the channel because authorization failed. */
    private val onAuthFailed: () -> Unit = {},
    private val log: (String) -> Unit = {},
) : PresenceChannelEventListener, PrivateEncryptedChannelEventListener {

    @Volatile
    var channel: Channel? = null

    override fun onEvent(event: PusherEvent) {
        val data = try {
            event.data
        } catch (e: Exception) {
            null
        }
        emit(
            EventBuilder.channelEvent(
                instanceId,
                event.channelName ?: channelName,
                event.eventName,
                data,
                event.userId,
            )
        )
    }

    override fun onSubscriptionSucceeded(channelName: String) {
        log("subscription succeeded: $channelName")
        val presence = channel as? PresenceChannel
        val users = if (presence != null) presence.users else null
        emit(EventBuilder.subscriptionSucceeded(instanceId, this.channelName, users))
    }

    override fun onAuthenticationFailure(message: String?, e: Exception?) {
        onAuthFailed()
        log("subscription error: $channelName status=${(e as? DartAuthorizationException)?.status} message=${message ?: e?.message}")
        val status = (e as? DartAuthorizationException)?.status
        emit(EventBuilder.subscriptionError(instanceId, channelName, message ?: e?.message, status))
    }

    override fun onError(message: String?, e: Exception?) {
        log("subscription error: $channelName message=${message ?: e?.message}")
        emit(EventBuilder.subscriptionError(instanceId, channelName, message ?: e?.message, null))
    }

    // The single subscription_succeeded is emitted from onSubscriptionSucceeded; nothing to do here.
    override fun onUsersInformationReceived(channelName: String, users: Set<User>) {}

    override fun userSubscribed(channelName: String, user: User) {
        emit(EventBuilder.memberAdded(instanceId, this.channelName, user))
    }

    override fun userUnsubscribed(channelName: String, user: User) {
        emit(EventBuilder.memberRemoved(instanceId, this.channelName, user))
    }

    override fun onDecryptionFailure(event: String?, reason: String?) {
        emit(EventBuilder.decryptionError(instanceId, channelName, event, reason))
    }
}
