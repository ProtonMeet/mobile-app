#include "proton_denoise_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#include "../common/desktop/desktop_audio_denoise.h"

namespace proton_denoise {

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

constexpr char kEffectsChannel[] = "me.proton.meet/denoise";
constexpr char kLegacyChannel[] = "proton_denoise";

std::string GetStringArg(const EncodableMap* args, const char* key) {
  if (!args) {
    return {};
  }
  auto it = args->find(EncodableValue(key));
  if (it == args->end()) {
    return {};
  }
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    return *s;
  }
  return {};
}

int GetIntArg(const EncodableMap* args, const char* key, int default_value) {
  if (!args) {
    return default_value;
  }
  auto it = args->find(EncodableValue(key));
  if (it == args->end()) {
    return default_value;
  }
  if (const auto* v = std::get_if<int32_t>(&it->second)) {
    return static_cast<int>(*v);
  }
  return default_value;
}

bool GetBoolArg(const EncodableMap* args, const char* key, bool default_value) {
  if (!args) {
    return default_value;
  }
  auto it = args->find(EncodableValue(key));
  if (it == args->end()) {
    return default_value;
  }
  if (const auto* v = std::get_if<bool>(&it->second)) {
    return *v;
  }
  return default_value;
}

EncodableList BuildDenoiseTypesList() {
  return EncodableList{
      EncodableMap{
          {EncodableValue("id"), EncodableValue("rnnoise")},
          {EncodableValue("displayName"), EncodableValue("RNNoise")},
          {EncodableValue("isReady"),
           EncodableValue(DesktopAudioDenoise::Instance().IsRnnoiseReady())},
      },
      EncodableMap{
          {EncodableValue("id"), EncodableValue("deepfilter")},
          {EncodableValue("displayName"), EncodableValue("DeepFilter")},
          {EncodableValue("isReady"), EncodableValue(false)},
      },
  };
}

}  // namespace

void ProtonDenoisePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto effects_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), kEffectsChannel,
          &flutter::StandardMethodCodec::GetInstance());
  auto legacy_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), kLegacyChannel,
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ProtonDenoisePlugin>();
  auto* plugin_ptr = plugin.get();

  effects_channel->SetMethodCallHandler(
      [plugin_ptr](const auto& call, auto result) {
        plugin_ptr->HandleEffectsCall(call, std::move(result));
      });
  legacy_channel->SetMethodCallHandler(
      [plugin_ptr](const auto& call, auto result) {
        plugin_ptr->HandleLegacyCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ProtonDenoisePlugin::ProtonDenoisePlugin() = default;

ProtonDenoisePlugin::~ProtonDenoisePlugin() = default;

void ProtonDenoisePlugin::HandleEffectsCall(
    const MethodCall<EncodableValue>& method_call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(method_call.arguments());
  const std::string track_id = GetStringArg(args, "trackId");
  const std::string type_id = GetStringArg(args, "type");

  const auto handled = DesktopAudioDenoise::Instance().Handle(
      kEffectsChannel, method_call.method_name(), track_id, type_id, false);

  if (!handled.success) {
    result->Error(handled.error_code, handled.error_message);
    return;
  }
  if (method_call.method_name() == "listDenoiseTypes") {
    result->Success(EncodableValue(BuildDenoiseTypesList()));
    return;
  }
  if (method_call.method_name() == "isTypeReady") {
    result->Success(EncodableValue(handled.bool_value));
    return;
  }
  result->Success();
}

void ProtonDenoisePlugin::HandleLegacyCall(
    const MethodCall<EncodableValue>& method_call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(method_call.arguments());
  const bool enabled = GetBoolArg(args, "enabled", false);

  if (method_call.method_name() == "processFrame") {
    if (!args) {
      result->Error("invalid_args", "Missing arguments");
      return;
    }
    auto samples_it = args->find(EncodableValue("samples"));
    if (samples_it == args->end()) {
      result->Error("invalid_args", "Missing samples");
      return;
    }
    const int channels = GetIntArg(args, "channels", 1);

    const auto& typed_data =
        std::get<flutter::EncodableTypedData>(samples_it->second).data();
    std::vector<uint8_t> buffer = typed_data;
    const size_t float_count = buffer.size() / sizeof(float);
    const auto processed = DesktopAudioDenoise::Instance().ProcessFrame(
        reinterpret_cast<float*>(buffer.data()), float_count,
        channels > 0 ? channels : 1);
    if (!processed.success) {
      result->Error(processed.error_code, processed.error_message);
      return;
    }

    EncodableMap response;
    response[EncodableValue("vad")] = EncodableValue(processed.float_value);
    response[EncodableValue("samples")] = EncodableValue(
        flutter::EncodableTypedData(flutter::EncodableTypedData::Float32,
                                    std::move(buffer)));
    result->Success(EncodableValue(response));
    return;
  }

  const auto handled = DesktopAudioDenoise::Instance().Handle(
      kLegacyChannel, method_call.method_name(), {}, {}, enabled);

  if (!handled.success) {
    result->Error(handled.error_code, handled.error_message);
    return;
  }
  if (method_call.method_name() == "create") {
    result->Success(EncodableValue(handled.bool_value));
    return;
  }
  if (method_call.method_name() == "getFrameSize") {
    result->Success(EncodableValue(handled.int_value));
    return;
  }
  if (method_call.method_name() == "isEnabled") {
    result->Success(EncodableValue(handled.bool_value));
    return;
  }
  result->Success();
}

}  // namespace proton_denoise
