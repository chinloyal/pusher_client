package com.github.chinloyal.pusher_client

import android.util.Log
import android.os.Handler
import android.os.Looper
import com.pusher.client.Pusher
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Flutter plugin entry point: wires the channels to a [PusherMethodHandler]. */
class PusherClientPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var handler: PusherMethodHandler? = null

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val main = Handler(Looper.getMainLooper())
        val mainExecutor: (Runnable) -> Unit = { r ->
            if (Looper.myLooper() == Looper.getMainLooper()) r.run() else main.post(r)
        }
        val channel = MethodChannel(binding.binaryMessenger, Protocol.METHOD_CHANNEL)
        val events = EventChannel(binding.binaryMessenger, Protocol.EVENT_CHANNEL)

        handler = PusherMethodHandler(
            pusherFactory = { key, options -> Pusher(key, options) },
            mainExecutor = mainExecutor,
            emitter = EventEmitter { event -> eventSink?.success(event) },
            logSink = { Log.d("PusherClientPlugin", it) },
            dartInvoker = DartInvoker { args, callback ->
                channel.invokeMethod(Protocol.AUTHORIZE_METHOD, args, object : MethodChannel.Result {
                    override fun success(result: Any?) = callback.success(result)
                    override fun error(code: String, message: String?, details: Any?) =
                        callback.error(code, message, details)

                    override fun notImplemented() = callback.notImplemented()
                })
            },
        )
        channel.setMethodCallHandler(this)
        events.setStreamHandler(this)
        methodChannel = channel
        eventChannel = events
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        handler?.disposeAll()
        handler = null
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val h = handler
        if (h == null) {
            result.error("NO_INSTANCE", "Plugin is detached from the engine", null)
            return
        }
        h.handle(call.method, call.arguments, object : Reply {
            override fun success(result2: Any?) = result.success(result2)
            override fun error(code: String, message: String?, details: Any?) = result.error(code, message, details)
            override fun notImplemented() = result.notImplemented()
        })
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
