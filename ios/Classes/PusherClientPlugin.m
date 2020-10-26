#import "PusherClientPlugin.h"
#if __has_include(<pusher_client/pusher_client-Swift.h>)
#import <pusher_client/pusher_client-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "pusher_client-Swift.h"
#endif

@implementation PusherClientPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftPusherClientPlugin registerWithRegistrar:registrar];
}
@end
