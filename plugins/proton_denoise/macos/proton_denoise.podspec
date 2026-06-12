#
# RNNoise + dtln-rs + optional DeepFilter — macOS (common/darwin via Classes symlinks).
#
require File.expand_path('../cocoapods/deepfilter_pod_support.rb', __dir__)

plugin_root = ProtonDenoiseDeepfilterPod.plugin_root_from(__dir__)
dtln_macos_lib = File.join(plugin_root, 'third_party/dtln-rs/lib/macos/libdtln.a')
verify_script = File.join(plugin_root, 'scripts/dtln/verify_dtln_apple_lib.sh')
dtln_macos_enabled =
  File.exist?(dtln_macos_lib) &&
  system('sh', verify_script, 'macosx', dtln_macos_lib)
deepfilter_macos_enabled = ProtonDenoiseDeepfilterPod.macos_enabled?(plugin_root)

rnnoise_out = '${BUILT_PRODUCTS_DIR}/librnnoise.a'
dtln_out = '${BUILT_PRODUCTS_DIR}/libdtln.a'
rnnoise_pod_force_load = '-force_load ${BUILT_PRODUCTS_DIR}/librnnoise.a'
dtln_pod_force_load = '-force_load ${BUILT_PRODUCTS_DIR}/libdtln.a'
rnnoise_app_force_load = '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/proton_denoise/librnnoise.a'
dtln_app_force_load = '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/proton_denoise/libdtln.a'

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

  s.platform = :osx, '12.0'
  s.swift_version = '5.0'
  s.library = 'c++'

  s.prepare_command = 'sh "${PWD}/../scripts/link_apple_pod_sources.sh" "${PWD}"'
  cpp_sources = [
    'Cpp/proton_rnnoise_c_api.cc',
    'Cpp/proton_rnnoise_processor.cc',
    'Cpp/proton_dtln_c_api.cc',
  ]
  cpp_sources << 'Cpp/proton_deepfilter_processor.cc' if deepfilter_macos_enabled
  s.source_files = ['Classes/**/*.swift', *cpp_sources]
  public_headers = [
    '../common/cpp/include/proton_rnnoise_api.h',
    '../common/cpp/include/proton_dtln_api.h',
  ]
  public_headers << '../common/cpp/include/proton_deepfilter_api.h' if deepfilter_macos_enabled
  s.public_header_files = public_headers
  s.resources = ['Resources/PrivacyInfo.xcprivacy']
  if deepfilter_macos_enabled
    ProtonDenoiseDeepfilterPod.apply_vendored_spec!(s, platform: :macos)
  end

  s.script_phases = [
    {
      :name => 'Build RNNoise',
      :script => 'export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/CMake.app/Contents/bin:${PATH}"; sh "${PODS_TARGET_SRCROOT}/../scripts/rnnoise/build_rnnoise_apple.sh"',
      :execution_position => :before_compile,
      :output_files => [rnnoise_out],
    },
    {
      :name => 'Stage DTLN',
      :script => 'sh "${PODS_TARGET_SRCROOT}/../scripts/dtln/stage_dtln_apple.sh"',
      :execution_position => :before_compile,
      :input_files => [
        '${PODS_TARGET_SRCROOT}/../third_party/dtln-rs/lib/macos/libdtln.a',
        '${PODS_TARGET_SRCROOT}/../scripts/dtln/stage_dtln_apple.sh',
        '${PODS_TARGET_SRCROOT}/../scripts/dtln/verify_dtln_apple_lib.sh',
      ],
      :output_files => [dtln_out],
    },
  ]

  pod_ldflags = "$(inherited) #{rnnoise_pod_force_load}"
  app_ldflags = "$(inherited) #{rnnoise_app_force_load}"
  if dtln_macos_enabled
    pod_ldflags += " #{dtln_pod_force_load}"
    app_ldflags += " #{dtln_app_force_load}"
  end

  swift_conditions = []
  swift_conditions << 'PROTON_DENOISE_DTLN_IOS' if dtln_macos_enabled
  swift_conditions << 'PROTON_DENOISE_DEEPFILTER' if deepfilter_macos_enabled
  header_search_paths = [
    '"${PODS_TARGET_SRCROOT}/Classes"',
    '"${PODS_TARGET_SRCROOT}/../third_party/rnnoise/include"',
    '"${PODS_TARGET_SRCROOT}/../third_party/dtln-rs/include"',
    '"${PODS_TARGET_SRCROOT}/../common/cpp/include"',
  ]
  header_search_paths << '"${PODS_TARGET_SRCROOT}/../third_party/deepfilter/include"' if deepfilter_macos_enabled
  pod_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => (header_search_paths + ['$(inherited)']).join(' '),
    'OTHER_LDFLAGS' => pod_ldflags,
  }
  user_target_xcconfig = {
    'OTHER_LDFLAGS' => app_ldflags,
  }
  if deepfilter_macos_enabled
    ProtonDenoiseDeepfilterPod.apply_link_settings!(
      pod_xcconfig,
      user_target_xcconfig,
      platform: :macos
    )
  end
  if swift_conditions.any?
    pod_xcconfig['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] =
      "$(inherited) #{swift_conditions.join(' ')}"
  end
  unless deepfilter_macos_enabled
    puts 'proton_denoise: DeepFilter disabled on macOS — run ./plugins/proton_denoise/scripts/deepfilter/build-deepfilter.sh macos when ready'
  end

  s.pod_target_xcconfig = pod_xcconfig
  s.user_target_xcconfig = user_target_xcconfig

  s.dependency 'FlutterMacOS'
  s.dependency 'flutter_webrtc'
end
