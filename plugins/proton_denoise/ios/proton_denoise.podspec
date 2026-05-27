#
# RNNoise — iOS (common/darwin via Classes symlinks + compile-time RNNoise).
#
rnnoise_out = '${BUILT_PRODUCTS_DIR}/librnnoise.a'
rnnoise_pod_force_load = '-force_load ${BUILT_PRODUCTS_DIR}/librnnoise.a'
rnnoise_app_force_load = '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/proton_denoise/librnnoise.a'

Pod::Spec.new do |s|
  s.name             = 'proton_denoise'
  s.version          = '1.0.0'
  s.summary          = 'RNNoise denoising for Proton Meet'
  s.description      = 'RNNoise plugin with flutter_webrtc local audio track integration.'
  s.homepage         = 'https://github.com/ProtonMeet'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Proton' => 'meet@proton.me' }
  s.source           = { :path => '.' }
  s.static_framework = true

  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.library = 'c++'

  s.source_files = [
    'Classes/**/*.swift',
    'Cpp/proton_rnnoise_c_api.cc',
    'Cpp/proton_rnnoise_processor.cc',
  ]
  s.public_header_files = '../common/cpp/include/proton_rnnoise_api.h'
  s.resources = ['Resources/PrivacyInfo.xcprivacy']

  s.script_phase = {
    :name => 'Build RNNoise',
    :script => 'export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/CMake.app/Contents/bin:${PATH}"; sh "${PODS_TARGET_SRCROOT}/../scripts/build_rnnoise_apple.sh"',
    :execution_position => :before_compile,
    :output_files => [rnnoise_out],
  }

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/Classes"',
      '"${PODS_TARGET_SRCROOT}/../third_party/rnnoise/include"',
      '"${PODS_TARGET_SRCROOT}/../common/cpp/include"',
      '$(inherited)',
    ].join(' '),
    'OTHER_LDFLAGS' => "$(inherited) #{rnnoise_pod_force_load}",
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => "$(inherited) #{rnnoise_app_force_load}",
  }

  s.dependency 'Flutter'
  s.dependency 'flutter_webrtc'
end
