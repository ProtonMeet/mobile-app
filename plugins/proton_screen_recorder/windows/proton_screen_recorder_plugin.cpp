#include "include/proton_screen_recorder/proton_screen_recorder_plugin_c_api.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

namespace proton_screen_recorder {

namespace {

using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

class ProtonScreenRecorderPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  ProtonScreenRecorderPlugin() = default;
  ~ProtonScreenRecorderPlugin() override = default;

 private:
  void HandleMethodCall(const MethodCall<EncodableValue>& method_call,
                        std::unique_ptr<MethodResult<EncodableValue>> result);
};

void ProtonScreenRecorderPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "screen_recording",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ProtonScreenRecorderPlugin>();
  auto* plugin_ptr = plugin.get();

  channel->SetMethodCallHandler(
      [plugin_ptr](const auto& call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

void ProtonScreenRecorderPlugin::HandleMethodCall(
    const MethodCall<EncodableValue>& method_call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto& method = method_call.method_name();

  if (method == "isSupported" || method == "isRecording") {
    result->Success(EncodableValue(false));
    return;
  }

  if (method == "startRecording" || method == "stopRecording") {
    result->Error("UNSUPPORTED",
                  "Screen recording is not yet supported on Windows");
    return;
  }

  result->NotImplemented();
}

}  // namespace

void ProtonScreenRecorderPluginRegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  ProtonScreenRecorderPlugin::RegisterWithRegistrar(registrar);
}

}  // namespace proton_screen_recorder
