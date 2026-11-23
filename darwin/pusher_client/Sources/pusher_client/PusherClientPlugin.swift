import Foundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

public class PusherClientPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let methodChannelName = "com.github.chinloyal/pusher_client"
    static let eventChannelName = "com.github.chinloyal/pusher_client_stream"

    let emitter = EventEmitter()
    var instances: [String: PusherInstance] = [:]
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?

    /// Overridable in tests: how `authorize` reaches Dart. Defaults to the method channel.
    var authorizeInvoker: AuthorizeInvoker?
    var authTimeout: TimeInterval = DartAuthorizer.defaultTimeout

    public static func register(with registrar: FlutterPluginRegistrar) {
        // The registrar's `messenger` is a method on iOS and a property on macOS.
        #if os(iOS)
        let messenger = registrar.messenger()
        #else
        let messenger = registrar.messenger
        #endif
        let plugin = PusherClientPlugin()
        let channel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
        let events = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
        plugin.methodChannel = channel
        plugin.eventChannel = events
        registrar.addMethodCallDelegate(plugin, channel: channel)
        events.setStreamHandler(plugin)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        disposeAll()
        methodChannel?.setMethodCallHandler(nil)
        eventChannel?.setStreamHandler(nil)
        methodChannel = nil
        eventChannel = nil
        emitter.sink = nil
    }

    // MARK: FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
        -> FlutterError?
    {
        emitter.sink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        emitter.sink = nil
        return nil
    }

    // MARK: Method calls

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.handle(call, result: result) }
            return
        }
        do {
            result(try perform(call))
        } catch let error as PluginError {
            result(error.flutterError)
        } catch {
            result(FlutterError(code: PluginErrorCode.invalidArguments.rawValue,
                                message: "\(error)", details: nil))
        }
    }

    /// Returns the value for the single reply. Never replies itself.
    private func perform(_ call: FlutterMethodCall) throws -> Any? {
        switch call.method {
        case "disposeAll":
            disposeAll()
            return nil
        case "init":
            let args = try Arguments.from(call.arguments)
            try initInstance(args)
            return nil
        case "dispose":
            let args = try Arguments.from(call.arguments)
            let id = try args.string("instanceId")
            instances.removeValue(forKey: id)?.dispose()
            return nil
        case "connect":
            try instance(call).connect()
            return nil
        case "disconnect":
            try instance(call).disconnect()
            return nil
        case "subscribe":
            let (instance, args) = try instanceAndArgs(call)
            instance.subscribe(channelName: try args.string("channelName"))
            return nil
        case "unsubscribe":
            let (instance, args) = try instanceAndArgs(call)
            instance.unsubscribe(channelName: try args.string("channelName"))
            return nil
        case "trigger":
            let (instance, args) = try instanceAndArgs(call)
            let channelName = try args.string("channelName")
            let eventName = try args.string("eventName")
            guard let data = args.map["data"] as? String else {
                throw PluginError.invalidArguments("Missing or invalid string argument 'data'.")
            }
            try instance.trigger(channelName: channelName, eventName: eventName, data: data)
            return nil
        case "getSocketId":
            return try instance(call).socketId
        default:
            return FlutterMethodNotImplemented
        }
    }

    private func instanceAndArgs(_ call: FlutterMethodCall) throws -> (PusherInstance, Arguments) {
        let args = try Arguments.from(call.arguments)
        let id = try args.string("instanceId")
        guard let instance = instances[id] else {
            throw PluginError(code: .noInstance, message: "No Pusher instance for id '\(id)'.")
        }
        return (instance, args)
    }

    private func instance(_ call: FlutterMethodCall) throws -> PusherInstance {
        return try instanceAndArgs(call).0
    }

    private func initInstance(_ args: Arguments) throws {
        let id = try args.string("instanceId")
        let appKey = try args.string("appKey")
        let enableLogging = try args.bool("enableLogging", default: false)
        let config = try PusherOptionsConfig.parse(args.map["options"])

        let invoker: AuthorizeInvoker = { [weak self] arguments, reply in
            if let custom = self?.authorizeInvoker {
                custom(arguments, reply)
            } else if let channel = self?.methodChannel {
                channel.invokeMethod("authorize", arguments: arguments, result: reply)
            } else {
                reply(FlutterMethodNotImplemented)
            }
        }
        let created = try PusherInstance(
            instanceId: id, appKey: appKey, enableLogging: enableLogging, config: config,
            emitter: emitter, authorizeInvoker: invoker, authTimeout: authTimeout)
        // Replace (and disconnect) any existing instance with the same id.
        instances.removeValue(forKey: id)?.dispose()
        instances[id] = created
        if enableLogging { NSLog("[pusher_client] init instance %@", id) }
    }

    func disposeAll() {
        let all = instances
        instances.removeAll()
        all.values.forEach { $0.dispose() }
    }
}
