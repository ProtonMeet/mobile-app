#
# Camera video effects for Proton Meet (background blur today; custom backgrounds later).
#
Pod::Spec.new do |s|
  s.name             = 'proton_video_effects'
  s.version          = '1.0.0'
  s.summary          = 'On-device camera video effects for Proton Meet'
  s.description      = 'MediaPipe selfie segmentation + background blur on flutter_webrtc local video tracks.'
  s.homepage         = 'https://github.com/ProtonMeet'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Proton' => 'meet@proton.me' }
  s.source           = { :path => '.' }
  # Build as static so MediaPipe + Flutter symbols are linked into the app (dynamic pods skip
  # static MediaPipe objects and you get undefined MPP* / Flutter* at link time).
  s.static_framework = true

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
  s.platform = :ios, '15.0'

  s.source_files = 'Classes/**/*'
  s.resources = ['Resources/*.tflite']
  s.dependency 'Flutter'
  s.dependency 'flutter_webrtc'
  s.dependency 'MediaPipeTasksVision', '0.10.35'


end
