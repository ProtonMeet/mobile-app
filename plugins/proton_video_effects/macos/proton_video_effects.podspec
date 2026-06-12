#
# macOS: reuses darwin/ blur bridge + Core Image compositor; Vision person segmentation
# (MediaPipeTasksVision CocoaPod is iOS-only).
#
Pod::Spec.new do |s|
  s.name             = 'proton_video_effects'
  s.version          = '1.0.0'
  s.summary          = 'On-device camera video effects for Proton Meet (macOS)'
  s.description      = 'Vision person segmentation + Core Image background blur on flutter_webrtc.'
  s.homepage         = 'https://github.com/ProtonMeet'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Proton' => 'meet@proton.me' }
  s.source           = { :path => '.' }

  s.static_framework = true
  s.platform = :osx, '12.0'
  s.swift_version = '5.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = 'Classes/**/*'
  s.frameworks = 'Vision', 'CoreImage', 'Metal'
  s.dependency 'FlutterMacOS'
  s.dependency 'flutter_webrtc'
end
