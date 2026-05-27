#ifndef FLUTTER_PLUGIN_PROTON_DENOISE_PLUGIN_H_
#define FLUTTER_PLUGIN_PROTON_DENOISE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace proton_denoise {

class ProtonDenoisePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  ProtonDenoisePlugin();
  ~ProtonDenoisePlugin() override;

  ProtonDenoisePlugin(const ProtonDenoisePlugin&) = delete;
  ProtonDenoisePlugin& operator=(const ProtonDenoisePlugin&) = delete;

 private:
  void HandleEffectsCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleLegacyCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace proton_denoise

#endif  // FLUTTER_PLUGIN_PROTON_DENOISE_PLUGIN_H_
