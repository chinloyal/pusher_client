package com.github.chinloyal.pusher_client

import com.pusher.client.Pusher
import com.pusher.client.PusherOptions
import com.pusher.client.channel.Channel
import com.pusher.client.channel.PrivateChannel
import com.pusher.client.connection.ConnectionEventListener
import com.pusher.client.connection.ConnectionState
import com.pusher.client.connection.ConnectionStateChange
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Dispatches Dart -> native method calls (§4) and owns every native Pusher instance.
 *
 * Collaborators are injected so the class can be unit tested on the JVM:
 * [pusherFactory] builds the library client, [mainExecutor] runs a block on the platform main thread,
 * [emitter] receives events for Dart and [dartInvoker] calls Dart's `authorize`.
 */
class PusherMethodHandler(
    private val pusherFactory: (String, PusherOptions) -> Pusher,
    private val mainExecutor: (Runnable) -> Unit,
    private val emitter: EventEmitter,
    private val dartInvoker: DartInvoker,
    private val authorizeTimeoutMs: Long = Protocol.AUTHORIZE_TIMEOUT_MS,
    private val logSink: (String) -> Unit = {},
) {
    private class Instance(val id: String, val pusher: Pusher, val log: (String) -> Unit) {
        @Volatile
        var disposed = false
        val channels = ConcurrentHashMap<String, Channel>()
    }

    private val instances = ConcurrentHashMap<String, Instance>()

    /** Handles one call and guarantees exactly one reply. */
    fun handle(method: String, arguments: Any?, reply: Reply) {
        val once = OnceReply(reply)
        try {
            when (method) {
                "disposeAll" -> {
                    disposeAll()
                    once.success(null)
                }
                "init" -> init(args(arguments), once)
                "connect" -> withInstance(arguments, once) { it.log("connect"); it.pusher.connect(); once.success(null) }
                "disconnect" -> withInstance(arguments, once) { it.log("disconnect"); it.pusher.disconnect(); once.success(null) }
                "dispose" -> {
                    val id = requireString(args(arguments), "instanceId")
                    instances.remove(id)?.let { it.log("dispose"); shutdown(it) }
                    once.success(null)
                }
                "subscribe" -> subscribe(arguments, once)
                "unsubscribe" -> unsubscribe(arguments, once)
                "trigger" -> trigger(arguments, once)
                "getSocketId" -> withInstance(arguments, once) { once.success(it.pusher.connection?.socketId) }
                else -> once.notImplemented()
            }
        } catch (e: InvalidArgumentsException) {
            once.error(Protocol.ERR_INVALID_ARGUMENTS, e.message)
        } catch (e: Exception) {
            once.error("PLUGIN_ERROR", e.message ?: e.toString())
        }
    }

    /** Disconnects and drops every instance. Safe to call at any time. */
    fun disposeAll() {
        val all = instances.values.toList()
        instances.clear()
        all.forEach { shutdown(it) }
    }

    // ---- methods ---------------------------------------------------------

    private fun init(args: Map<*, *>, reply: Reply) {
        val id = requireString(args, "instanceId")
        val appKey = requireString(args, "appKey")
        val optionsMap = args["options"] as? Map<*, *>
            ?: throw InvalidArgumentsException("'options' must be a Map")
        val enableLogging = args["enableLogging"]
        if (enableLogging != null && enableLogging !is Boolean) {
            throw InvalidArgumentsException("'enableLogging' must be a bool")
        }
        val log: (String) -> Unit = if (enableLogging == true) { m -> logSink("[$id] $m") } else { _ -> }
        val authorizer = DartChannelAuthorizer(id, dartInvoker, mainExecutor, authorizeTimeoutMs, log)
        val options = OptionsMapper.toPusherOptions(optionsMap, authorizer)

        val instance = try {
            val pusher = pusherFactory(appKey, options)
            Instance(id, pusher, log).also { inst ->
                // Bound exactly once; connect() is later called without a listener.
                pusher.connection.bind(ConnectionState.ALL, connectionListener(inst))
            }
        } catch (e: Exception) {
            reply.error(Protocol.ERR_INIT, e.message ?: e.toString())
            return
        }
        instances.put(id, instance)?.let { shutdown(it) }
        log("init appKey=$appKey")
        reply.success(null)
    }

    private fun subscribe(arguments: Any?, reply: Reply) {
        val args = args(arguments)
        val name = requireString(args, "channelName")
        val instance = lookup(args, reply) ?: return
        if (instance.channels.containsKey(name)) {
            reply.success(null) // idempotent
            return
        }
        try {
            instance.log("subscribe $name")
            val forwarder = ChannelEventForwarder(
                instance.id,
                name,
                emit = { emit(instance, it) },
                // pusher-java forgets the channel after an auth failure, so allow subscribing again.
                onAuthFailed = { instance.channels.remove(name) },
                log = instance.log,
            )
            val pusher = instance.pusher
            val channel: Channel = when {
                name.startsWith("private-encrypted-") -> pusher.subscribePrivateEncrypted(name, forwarder)
                name.startsWith("private-") -> pusher.subscribePrivate(name, forwarder)
                name.startsWith("presence-") -> pusher.subscribePresence(name, forwarder)
                else -> pusher.subscribe(name, forwarder)
            }
            forwarder.channel = channel
            channel.bindGlobal(forwarder)
            instance.channels[name] = channel
            reply.success(null)
        } catch (e: Exception) {
            reply.error(Protocol.ERR_SUBSCRIBE, e.message ?: e.toString())
        }
    }

    private fun unsubscribe(arguments: Any?, reply: Reply) {
        val args = args(arguments)
        val name = requireString(args, "channelName")
        val instance = lookup(args, reply) ?: return
        try {
            instance.log("unsubscribe $name")
            instance.channels.remove(name)
            instance.pusher.unsubscribe(name)
            reply.success(null)
        } catch (e: Exception) {
            reply.error(Protocol.ERR_UNSUBSCRIBE, e.message ?: e.toString())
        }
    }

    private fun trigger(arguments: Any?, reply: Reply) {
        val args = args(arguments)
        val name = requireString(args, "channelName")
        val eventName = requireString(args, "eventName")
        val data = requireString(args, "data")
        val instance = lookup(args, reply) ?: return

        val clientEventChannel = (name.startsWith("private-") && !name.startsWith("private-encrypted-")) ||
            name.startsWith("presence-")
        if (!clientEventChannel) {
            reply.error(Protocol.ERR_TRIGGER, "Client events can only be triggered on private and presence channels")
            return
        }
        val channel = instance.channels[name] as? PrivateChannel
        if (channel == null) {
            reply.error(Protocol.ERR_TRIGGER, "Not subscribed to channel $name")
            return
        }
        try {
            instance.log("trigger $name $eventName")
            channel.trigger(eventName, data)
            reply.success(null)
        } catch (e: Exception) {
            reply.error(Protocol.ERR_TRIGGER, e.message ?: e.toString())
        }
    }

    // ---- helpers ---------------------------------------------------------

    private inline fun withInstance(arguments: Any?, reply: Reply, block: (Instance) -> Unit) {
        val instance = lookup(args(arguments), reply) ?: return
        block(instance)
    }

    /** Returns the instance or replies NO_INSTANCE. */
    private fun lookup(args: Map<*, *>, reply: Reply): Instance? {
        val id = requireString(args, "instanceId")
        val instance = instances[id]
        if (instance == null) reply.error(Protocol.ERR_NO_INSTANCE, "No Pusher instance with id $id")
        return instance
    }

    private fun args(arguments: Any?): Map<*, *> =
        arguments as? Map<*, *> ?: throw InvalidArgumentsException("Arguments must be a Map")

    private fun requireString(args: Map<*, *>, key: String): String {
        val v = args[key] ?: throw InvalidArgumentsException("Missing argument '$key'")
        return v as? String ?: throw InvalidArgumentsException("Argument '$key' must be a String")
    }

    private fun shutdown(instance: Instance) {
        instance.disposed = true
        try {
            instance.pusher.disconnect()
        } catch (e: Exception) {
            // Best effort.
        }
        instance.channels.clear()
    }

    private fun emit(instance: Instance, event: Map<String, Any?>) {
        mainExecutor(Runnable {
            if (!instance.disposed) emitter.emit(event)
        })
    }

    private fun connectionListener(instance: Instance) = object : ConnectionEventListener {
        override fun onConnectionStateChange(change: ConnectionStateChange) {
            val socketId = try {
                instance.pusher.connection?.socketId
            } catch (e: Exception) {
                null
            }
            instance.log("state ${change.previousState} -> ${change.currentState}")
            emit(
                instance,
                EventBuilder.connectionStateChange(
                    instance.id,
                    change.currentState,
                    change.previousState,
                    if (change.currentState == ConnectionState.CONNECTED) socketId else null,
                ),
            )
        }

        override fun onError(message: String?, code: String?, e: Exception?) {
            instance.log("connection error: code=$code message=$message")
            emit(instance, EventBuilder.connectionError(instance.id, message, code, e?.toString()))
        }
    }

    /** Ensures a call is answered at most once. */
    private class OnceReply(private val delegate: Reply) : Reply {
        private val replied = AtomicBoolean(false)
        override fun success(result: Any?) {
            if (replied.compareAndSet(false, true)) delegate.success(result)
        }

        override fun error(code: String, message: String?, details: Any?) {
            if (replied.compareAndSet(false, true)) delegate.error(code, message, details)
        }

        override fun notImplemented() {
            if (replied.compareAndSet(false, true)) delegate.notImplemented()
        }
    }
}
