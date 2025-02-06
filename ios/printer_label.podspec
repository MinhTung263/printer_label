Pod::Spec.new do |s|
  s.name             = 'printer_label'
  s.version          = '0.0.1'
  s.summary          = 'A Flutter plugin for printer label support.'
  s.description      = <<-DESC
  This plugin allows Flutter apps to interact with Bluetooth printers.
  DESC
  s.homepage         = 'https://your-website.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your@email.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.frameworks       = 'CoreBluetooth'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'

  s.ios.deployment_target = '12.0'
  s.preserve_paths = 'Classes/**/*'
  s.swift_version = '5.0'

  flutter_root = `flutter --version`.lines.last.split(' ').last.strip
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-framework Flutter'
  }
  s.xcconfig = { 'HEADER_SEARCH_PATHS' => "$(inherited) $(SDKROOT)/usr/include" }
  s.vendored_frameworks = "#{flutter_root}/bin/cache/artifacts/engine/ios-release/Flutter.xcframework"
end
