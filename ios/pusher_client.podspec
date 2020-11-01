#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pusher_client.podspec' to validate before publishing.
#
require 'yaml'
pubspec = YAML.load_file(File.join('..', 'pubspec.yaml'))
libraryVersion = pubspec['version'].gsub('+', '-')

Pod::Spec.new do |s|
  s.name             = 'pusher_client'
  s.version          = libraryVersion
  s.summary          = 'A pusher client plugin.'
  s.description      = <<-DESC
A pusher client plugin that works.
                       DESC
  s.homepage         = 'https://github.com/chinloyal/pusher_client'
  s.license          = { :file => '../LICENSE', :type => 'MIT' }
  s.author           = { 'Romario Chinloy' => 'jordain7@protonmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'PusherSwiftWithEncryption', '~> 8.0.0'
  s.platform = :ios, '9.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
