Pod::Spec.new do |s|
  s.name             = 'printer_label'
  s.version          = '0.0.1'
  s.summary          = 'A Flutter plugin for printer label support.'
  s.description      = <<-DESC
  This plugin allows Flutter apps to interact with printer label.
  DESC
  s.homepage         = 'https://github.com/MinhTung263/printer_label'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your@email.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m,swift,a}'
  s.public_header_files = 'Classes/**/*.h'
  s.static_framework = true
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.ios.deployment_target = '12.0'
  s.swift_version = '5.0'
  s.vendored_libraries = '**/*.a'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-framework Flutter'
  }
end
