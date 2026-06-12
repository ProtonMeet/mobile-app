# Shared DeepFilter CocoaPods settings for ios/ and macos/ podspecs.
# Vendored binaries and the ONNX model are symlinked under each platform pod
# root by scripts/link_apple_pod_sources.sh (prepare_command).
module ProtonDenoiseDeepfilterPod
  DEEPFILTER_RESOURCE_BUNDLE = 'proton_denoise_deepfilter'
  MODEL_RESOURCE = 'Resources/DeepFilterNet3_onnx.tar.gz'

  def self.plugin_root_from(platform_dir)
    File.expand_path('..', platform_dir)
  end

  def self.ios_enabled?(plugin_root)
    xc = File.join(plugin_root, 'third_party/deepfilter/ios/DeepFilter.xcframework')
    model = File.join(plugin_root, 'third_party/deepfilter/models/DeepFilterNet3_onnx.tar.gz')
    File.directory?(xc) && File.exist?(model)
  end

  def self.macos_enabled?(plugin_root)
    fw = File.join(plugin_root, 'third_party/deepfilter/macos/DeepFilter.framework')
    model = File.join(plugin_root, 'third_party/deepfilter/models/DeepFilterNet3_onnx.tar.gz')
    File.directory?(fw) && File.exist?(model)
  end

  def self.apply_link_settings!(pod_xcconfig, user_target_xcconfig, platform:)
    pod_ldflags = pod_xcconfig.fetch('OTHER_LDFLAGS', '$(inherited)')
    app_ldflags = user_target_xcconfig.fetch('OTHER_LDFLAGS', '$(inherited)')
    pod_xcconfig['OTHER_LDFLAGS'] = "#{pod_ldflags} -framework DeepFilter"
    user_target_xcconfig['OTHER_LDFLAGS'] = "#{app_ldflags} -framework DeepFilter"

    case platform
    when :ios
      pod_paths = [
        '"${PODS_XCFRAMEWORKS_BUILD_DIR}/proton_denoise"',
        '"${PODS_TARGET_SRCROOT}/Vendored/DeepFilter.xcframework/ios-arm64"',
        '"${PODS_TARGET_SRCROOT}/Vendored/DeepFilter.xcframework/ios-arm64_x86_64-simulator"',
      ]
      app_paths = [
        '"${PODS_XCFRAMEWORKS_BUILD_DIR}/proton_denoise"',
        '"${PODS_ROOT}/../.symlinks/plugins/proton_denoise/ios/Vendored/DeepFilter.xcframework/ios-arm64"',
        '"${PODS_ROOT}/../.symlinks/plugins/proton_denoise/ios/Vendored/DeepFilter.xcframework/ios-arm64_x86_64-simulator"',
      ]
      user_target_xcconfig['LD_RUNPATH_SEARCH_PATHS'] =
        '$(inherited) @executable_path/Frameworks'
    when :macos
      pod_paths = [
        '"${PODS_CONFIGURATION_BUILD_DIR}/proton_denoise"',
        '"${PODS_TARGET_SRCROOT}/Vendored"',
      ]
      app_paths = [
        '"${PODS_CONFIGURATION_BUILD_DIR}/proton_denoise"',
        '"${PODS_ROOT}/../Flutter/ephemeral/.symlinks/plugins/proton_denoise/macos/Vendored"',
      ]
      user_target_xcconfig['LD_RUNPATH_SEARCH_PATHS'] =
        '$(inherited) @executable_path/../Frameworks'
    else
      return
    end

    pod_xcconfig['FRAMEWORK_SEARCH_PATHS'] =
      (pod_paths + ['$(inherited)']).join(' ')
    user_target_xcconfig['FRAMEWORK_SEARCH_PATHS'] =
      (app_paths + ['$(inherited)']).join(' ')
  end

  def self.apply_vendored_spec!(spec, platform:)
    case platform
    when :ios
      spec.vendored_frameworks = 'Vendored/DeepFilter.xcframework'
    when :macos
      spec.vendored_frameworks = 'Vendored/DeepFilter.framework'
    end
    spec.resource_bundles = {
      DEEPFILTER_RESOURCE_BUNDLE => [MODEL_RESOURCE],
    }
  end
end
