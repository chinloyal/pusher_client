#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pusher_client.podspec` to validate before publishing.
#
require 'yaml'

pubspec = YAML.load_file(File.join(__dir__, '..', 'pubspec.yaml'))

Pod::Spec.new do |s|
  s.name             = 'pusher_client'
  s.version          = pubspec['version']
  s.summary          = 'Pusher Channels client for Flutter (iOS and macOS).'
  s.description      = <<-DESC
Flutter plugin wrapping pusher-websocket-swift. Shared Swift implementation for iOS and macOS.
                       DESC
  s.homepage         = 'https://github.com/chinloyal/pusher_client'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Romario Chinloy' => 'https://github.com/chinloyal' }
  s.source           = { :path => '.' }
  s.source_files     = 'pusher_client/Sources/pusher_client/**/*.swift'

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.dependency 'PusherSwift', '~> 10.1.10'
  # Same constraint PusherSwift 10.1.10 uses; imported for SubscriptionDataNormalizer.
  s.dependency 'NWWebSocket', '~> 0.5.10'

  # Flutter.framework does not contain a i386 slice.
  s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.swift_version = '5.0'

  s.resource_bundles = {'pusher_client_privacy' => ['pusher_client/Sources/pusher_client/PrivacyInfo.xcprivacy']}
end
