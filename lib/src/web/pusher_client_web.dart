import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import '../platform/pusher_platform.dart';
import 'web_pusher_platform.dart';

/// Web plugin registration: routes the plugin through pusher-js.
class PusherClientWeb {
  /// Registers this plugin on the web.
  static void registerWith(Registrar registrar) {
    PusherPlatform.instance = WebPusherPlatform();
  }
}
