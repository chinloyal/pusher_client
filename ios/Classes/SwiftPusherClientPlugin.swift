import Flutter
import UIKit

public class SwiftPusherClientPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    PusherService().register(messenger: registrar.messenger())
  }
}
