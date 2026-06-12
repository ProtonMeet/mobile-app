#
# RNNoise + optional dtln-rs — iOS (common/darwin via Classes symlinks).
#
require File.expand_path('../cocoapods/deepfilter_pod_support.rb', __dir__)

plugin_root = ProtonDenoiseDeepfilterPod.plugin_root_from(__dir__)
dtln_ios_lib = File.join(plugin_root, 'third_party/dtln-rs/lib/ios/device/libdtln.a')
verify_script = File.join(plugin_root, 'scripts/dtln/verify_dtln_apple_lib.sh')
dtln_ios_enabled =
  File.exist?(dtln_ios_lib) &&
  system('sh', verify_script, 'iphoneos', dtln_ios_lib)
deepfilter_ios_enabled = ProtonDenoiseDeepfilterPod.ios_enabled?(plugin_root)

rnnoise_out = '${BUILT_PRODUCTS_DIR}/librnnoise.a'
dtln_out = '${BUILT_PRODUCTS_DIR}/libdtln.a'
dtln_tflite_out = '${BUILT_PRODUCTS_DIR}/libdtln_tflite.a'
rnnoise_pod_force_load = '-force_load ${BUILT_PRODUCTS_DIR}/librnnoise.a'
dtln_pod_force_load = '-force_load ${BUILT_PRODUCTS_DIR}/libdtln.a'
dtln_tflite_pod_force_load = '-force_load ${BUILT_PRODUCTS_DIR}/libdtln_tflite.a'
rnnoise_app_force_load = '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/proton_denoise/librnnoise.a'
dtln_app_force_load = '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/proton_denoise/libdtln.a'

cpp_sources = [
  'Cpp/proton_rnnoise_c_api.cc',
  'Cpp/proton_rnnoise_processor.cc',
]
cpp_sources << 'Cpp/proton_dtln_c_api.cc' if dtln_ios_enabled
cpp_sources << 'Cpp/proton_deepfilter_processor.cc' if deepfilter_ios_enabled
public_headers = ['../common/cpp/include/proton_rnnoise_api.h']
public_headers << '../common/cpp/include/proton_dtln_api.h' if dtln_ios_enabled
public_headers << '../common/cpp/include/proton_deepfilter_api.h' if deepfilter_ios_enabled

script_phases = [
  {
    :name => 'Build RNNoise',
    :script => 'export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/CMake.app/Contents/bin:${PATH}"; sh "${PODS_TARGET_SRCROOT}/../scripts/rnnoise/build_rnnoise_apple.sh"',
    :execution_position => :before_compile,
    :output_files => [rnnoise_out],
  },
]
if dtln_ios_enabled
  script_phases << {
    :name => 'Stage DTLN',
    :script => 'mkdir -p "${BUILT_PRODUCTS_DIR}" && sh "${PODS_TARGET_SRCROOT}/../scripts/dtln/stage_dtln_apple.sh"',
    :execution_position => :before_compile,
    :input_files => [
      '${PODS_TARGET_SRCROOT}/../third_party/dtln-rs/lib/ios/device/libdtln.a',
      '${PODS_TARGET_SRCROOT}/../third_party/dtln-rs/lib/ios/device/libdtln_tflite.a',
      '${PODS_TARGET_SRCROOT}/../third_party/dtln-rs/lib/ios/simulator/libdtln.a',
      '${PODS_TARGET_SRCROOT}/../third_party/dtln-rs/lib/ios/simulator/libdtln_tflite.a',
      '${PODS_TARGET_SRCROOT}/../scripts/dtln/stage_dtln_apple.sh',
      '${PODS_TARGET_SRCROOT}/../scripts/dtln/verify_dtln_apple_lib.sh',
    ],
    :output_files => [dtln_out, dtln_tflite_out],
  }
end

pod_ldflags = "$(inherited) #{rnnoise_pod_force_load}"
app_ldflags = "$(inherited) #{rnnoise_app_force_load}"
if dtln_ios_enabled
  pod_ldflags += " #{dtln_pod_force_load} #{dtln_tflite_pod_force_load}"
  app_ldflags += " #{dtln_app_force_load}"
end

header_search_paths = [
  '"${PODS_TARGET_SRCROOT}/Classes"',
  '"${PODS_TARGET_SRCROOT}/../third_party/rnnoise/include"',
  '"${PODS_TARGET_SRCROOT}/../common/cpp/include"',
]
header_search_paths << '"${PODS_TARGET_SRCROOT}/../third_party/dtln-rs/include"' if dtln_ios_enabled
header_search_paths << '"${PODS_TARGET_SRCROOT}/../third_party/deepfilter/include"' if deepfilter_ios_enabled

pod_xcconfig = {
  'DEFINES_MODULE' => 'YES',
  'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
  'HEADER_SEARCH_PATHS' => (header_search_paths + ['$(inherited)']).join(' '),
  'OTHER_LDFLAGS' => pod_ldflags,
}
user_target_xcconfig = {
  'OTHER_LDFLAGS' => app_ldflags,
}
if deepfilter_ios_enabled
  ProtonDenoiseDeepfilterPod.apply_link_settings!(
    pod_xcconfig,
    user_target_xcconfig,
    platform: :ios
  )
end

swift_conditions = []
swift_conditions << 'PROTON_DENOISE_DTLN_IOS' if dtln_ios_enabled
swift_conditions << 'PROTON_DENOISE_DEEPFILTER' if deepfilter_ios_enabled
if swift_conditions.any?
  pod_xcconfig['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] =
    "$(inherited) #{swift_conditions.join(' ')}"
else
  puts 'proton_denoise: DTLN disabled on iOS — rebuild with ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh ios when ready'
end
unless deepfilter_ios_enabled
  puts 'proton_denoise: DeepFilter disabled on iOS — run ./plugins/proton_denoise/scripts/deepfilter/build-deepfilter.sh ios when ready'
end

Pod::Spec.new do |s|
  s.name             = 'proton_denoise'
  s.version          = '1.0.0'
  s.summary          = 'Audio denoising for Proton Meet'
  s.description      = 'RNNoise and dtln-rs denoise with flutter_webrtc local audio track integration.'
  s.homepage         = 'https://github.com/ProtonMeet'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Proton' => 'meet@proton.me' }
  s.source           = { :path => '.' }
  s.static_framework = true

  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.library = 'c++'

  s.prepare_command = 'sh "${PWD}/../scripts/link_apple_pod_sources.sh" "${PWD}"'
  s.source_files = ['Classes/**/*.swift', *cpp_sources]
  s.public_header_files = public_headers
  s.resources = ['Resources/PrivacyInfo.xcprivacy']
  if deepfilter_ios_enabled
    ProtonDenoiseDeepfilterPod.apply_vendored_spec!(s, platform: :ios)
  end
  s.script_phases = script_phases
  s.pod_target_xcconfig = pod_xcconfig
  s.user_target_xcconfig = user_target_xcconfig

  s.dependency 'Flutter'
  s.dependency 'flutter_webrtc'
end
