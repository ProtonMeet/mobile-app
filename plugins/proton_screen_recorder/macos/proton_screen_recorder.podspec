#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint proton_screen_recorder.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'proton_screen_recorder'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'proton_screen_recorder/Sources/proton_screen_recorder/**/*.swift'

  s.resource_bundles = {'proton_screen_recorder_privacy' => ['proton_screen_recorder/Sources/proton_screen_recorder/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'
  s.frameworks = 'CoreGraphics', 'AVFoundation', 'ScreenCaptureKit', 'ReplayKit'

  s.platform = :osx, '11.5'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
