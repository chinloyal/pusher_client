package com.github.chinloyal.pusher_client

/** Method / event names and error codes shared with the Dart layer (doc/architecture.md §3-§7). */
internal object Protocol {
    const val METHOD_CHANNEL = "com.github.chinloyal/pusher_client"
    const val EVENT_CHANNEL = "com.github.chinloyal/pusher_client_stream"

    const val AUTHORIZE_METHOD = "authorize"
    const val AUTHORIZE_TIMEOUT_MS = 30_000L

    const val ERR_INIT = "INIT_ERROR"
    const val ERR_NO_INSTANCE = "NO_INSTANCE"
    const val ERR_INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
    const val ERR_SUBSCRIBE = "SUBSCRIBE_ERROR"
    const val ERR_UNSUBSCRIBE = "UNSUBSCRIBE_ERROR"
    const val ERR_TRIGGER = "TRIGGER_ERROR"
    const val ERR_AUTH = "AUTH_ERROR"
}

/** Thrown for missing / wrongly typed arguments; replied as `INVALID_ARGUMENTS`. */
internal class InvalidArgumentsException(message: String) : Exception(message)

/** Result sink for one method call (decoupled from Flutter so it can be unit tested). */
interface Reply {
    fun success(result: Any?)
    fun error(code: String, message: String?, details: Any? = null)
    fun notImplemented()
}

/** Receives events destined for the Dart EventChannel. Always called on the main thread. */
fun interface EventEmitter {
    fun emit(event: Map<String, Any?>)
}
