#include "include/proton_video_effects/proton_video_effects_plugin_c_api.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <memory>
#include <string>

#include "../common/desktop/desktop_background_blur.h"

namespace proton_video_effects {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

std::string GetStringArg(const EncodableMap* args, const char* key) {
  if (!args) {
    return {};
  }
  auto it = args->find(EncodableValue(key));
  if (it == args->end()) {
    return {};
  }
  const auto* value = std::get_if<std::string>(&it->second);
  return value ? *value : std::string();
}

double GetDoubleArg(const EncodableMap* args,
                    const char* key,
                    double default_value) {
  if (!args) {
    return default_value;
  }
  auto it = args->find(EncodableValue(key));
  if (it == args->end()) {
    return default_value;
  }
  // Dart doubles arrive as double; whole numbers may arrive as int.
  if (const auto* v = std::get_if<double>(&it->second)) {
    return *v;
  }
  if (const auto* v = std::get_if<int32_t>(&it->second)) {
    return static_cast<double>(*v);
  }
  if (const auto* v = std::get_if<int64_t>(&it->second)) {
    return static_cast<double>(*v);
  }
  return default_value;
}

meet_video_effects::DesktopBlurConfig ParseBlurConfig(
    const EncodableMap* args) {
  meet_video_effects::DesktopBlurConfig config;
  config.blur_sigma = GetDoubleArg(args, "blurSigma", config.blur_sigma);
  config.background_obscure_opacity = GetDoubleArg(
      args, "backgroundObscureOpacity", config.background_obscure_opacity);
  const std::string mode = GetStringArg(args, "backgroundMode");
  if (!mode.empty()) {
    config.background_mode = mode;
  }
  config.replacement_image_path = GetStringArg(args, "replacementImagePath");
  // A missing mask key falls back to the default rather than the current value:
  // Dart always sends the complete set, so a gap means an older client, and the
  // defaults are what that client expects to get.
  auto& edge = config.mask_edge;
  edge.feather_height_fraction = GetDoubleArg(args, "maskFeatherHeightFraction",
                                              edge.feather_height_fraction);
  edge.erode_height_fraction =
      GetDoubleArg(args, "maskErodeHeightFraction", edge.erode_height_fraction);
  edge.solidify_slope =
      GetDoubleArg(args, "maskSolidifySlope", edge.solidify_slope);
  edge.solidify_midpoint =
      GetDoubleArg(args, "maskSolidifyMidpoint", edge.solidify_midpoint);
  edge.foreground_gamma =
      GetDoubleArg(args, "maskForegroundGamma", edge.foreground_gamma);
  return config;
}

meet_video_effects::DesktopReplacementRequest ParseReplacementRequest(
    const EncodableMap* args) {
  meet_video_effects::DesktopReplacementRequest request;
  request.mode_is_blur = GetStringArg(args, "backgroundMode") == "blur";
  if (request.mode_is_blur) {
    return request;
  }
  request.path = GetStringArg(args, "replacementImagePath");
  if (request.path.empty()) {
    request.path = GetStringArg(args, "filePath");
  }
  if (!request.path.empty() || !args) {
    return request;
  }
  auto it = args->find(EncodableValue("imageBytes"));
  if (it != args->end()) {
    if (const auto* bytes = std::get_if<std::vector<uint8_t>>(&it->second)) {
      request.bytes = *bytes;
    }
  }
  return request;
}

class ProtonVideoEffectsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  ProtonVideoEffectsPlugin();

  ~ProtonVideoEffectsPlugin() override;

 private:
  void HandleMethodCall(const MethodCall<EncodableValue>& method_call,
                        std::unique_ptr<MethodResult<EncodableValue>> result);
};

void ProtonVideoEffectsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), "me.proton.meet/video_effects",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ProtonVideoEffectsPlugin>();
  auto* plugin_ptr = plugin.get();

  channel->SetMethodCallHandler(
      [plugin_ptr](const auto& call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));

  HMODULE module = nullptr;
  if (GetModuleHandleExA(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCSTR>(&ProtonVideoEffectsPlugin::RegisterWithRegistrar),
          &module)) {
    char module_path[MAX_PATH];
    const DWORD len = GetModuleFileNameA(module, module_path, MAX_PATH);
    if (len > 0) {
      std::string dir(module_path, len);
      const auto pos = dir.find_last_of("\\/");
      if (pos != std::string::npos) {
        dir.resize(pos);
        meet_video_effects::DesktopBackgroundBlur::Instance().SetModelsDirectory(dir);
      }
    }
  }
}

ProtonVideoEffectsPlugin::ProtonVideoEffectsPlugin() = default;

ProtonVideoEffectsPlugin::~ProtonVideoEffectsPlugin() = default;

void ProtonVideoEffectsPlugin::HandleMethodCall(
    const MethodCall<EncodableValue>& method_call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(method_call.arguments());
  const std::string track_id = GetStringArg(args, "trackId");
  const std::string& method = method_call.method_name();
  auto& blur = meet_video_effects::DesktopBackgroundBlur::Instance();

  // Config and model methods are accepted rather than reported as
  // NOT_IMPLEMENTED: Dart rethrows PlatformException for them, which would
  // surface as an error for settings the desktop engine simply ignores.
  if (method == "setBackgroundBlurConfig") {
    blur.SetConfig(ParseBlurConfig(args));
    blur.ApplyReplacementRequest(ParseReplacementRequest(args));
    result->Success();
    return;
  }
  if (method == "setSegmentationModel") {
    blur.SetSegmentationModel(GetStringArg(args, "model"));
    result->Success();
    return;
  }
  if (method == "getSegmentationModel") {
    const auto info = blur.SegmentationModelInfo();
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("model"), EncodableValue(info.model)},
        {EncodableValue("backend"), EncodableValue(info.backend)},
        {EncodableValue("forced"), EncodableValue(info.forced)},
        {EncodableValue("supported"), EncodableValue(info.supported)},
        {EncodableValue("reason"), EncodableValue(info.reason)},
    }));
    return;
  }
  if (method == "setReplacementBackgroundImage") {
    if (blur.ApplyReplacementRequest(ParseReplacementRequest(args))) {
      result->Success();
    } else {
      result->Error("IMAGE", "Failed to decode replacement image");
    }
    return;
  }
  if (method == "clearReplacementBackground") {
    blur.ClearReplacementImage();
    result->Success();
    return;
  }

  // attach/detach also carry config args; apply them before attaching.
  if (method == "attach" || method == "attachBackgroundBlur") {
    blur.SetConfig(ParseBlurConfig(args));
    blur.ApplyReplacementRequest(ParseReplacementRequest(args));
  }

  const auto handled = blur.Handle(method, track_id);

  if (!handled.success) {
    result->Error(handled.error_code, handled.error_message);
    return;
  }
  if (handled.has_string_value) {
    result->Success(EncodableValue(handled.string_value));
    return;
  }
  if (handled.has_bool_value) {
    result->Success(EncodableValue(handled.bool_value));
    return;
  }
  result->Success();
}

}  // namespace

}  // namespace proton_video_effects

void ProtonVideoEffectsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  proton_video_effects::ProtonVideoEffectsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
