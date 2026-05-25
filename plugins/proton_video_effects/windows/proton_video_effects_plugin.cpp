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
  std::string track_id;
  const auto* args = std::get_if<EncodableMap>(method_call.arguments());
  if (args) {
    auto it = args->find(EncodableValue("trackId"));
    if (it != args->end()) {
      if (const auto* id = std::get_if<std::string>(&it->second)) {
        track_id = *id;
      }
    }
  }

  const auto handled = meet_video_effects::DesktopBackgroundBlur::Instance().Handle(
      method_call.method_name(), track_id);

  if (!handled.success) {
    result->Error(handled.error_code, handled.error_message);
    return;
  }
  if (method_call.method_name() == "isImplementationReady" ||
      method_call.method_name() == "isBackgroundBlurReady") {
    result->Success(EncodableValue(handled.bool_value));
    return;
  }
  result->Success();
}

}  // namespace

}  // namespace proton_video_effects

void ProtonVideoEffectsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  proton_video_effects::ProtonVideoEffectsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
