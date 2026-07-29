Pod::Spec.new do |s|
  s.name             = 'printer_label'
  s.version          = '0.0.1'
  s.summary          = 'A Flutter plugin for printer label support.'
  s.description      = <<-DESC
This plugin allows Flutter apps to interact with printer label.
DESC

  s.homepage         = 'https://github.com/MinhTung263/printer_label'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Minh Tung' => 'your@email.com' }
  s.source           = { :path => '.' }

  # ✅ ĐÚNG PATH
  s.source_files = 'Classes/**/*.swift'

  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.dependency 'Flutter'

  # ✅ XCFramework
  s.vendored_frameworks = 'Classes/PrinterSDK.xcframework'

  s.static_framework = true
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'
  }
end
