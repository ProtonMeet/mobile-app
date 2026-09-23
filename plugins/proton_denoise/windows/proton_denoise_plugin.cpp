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
  // Dart ints arrive as int32_t or int64_t depending on magnitude.
  if (const auto* v = std::get_if<int32_t>(&it->second)) {
    return static_cast<int>(*v);
  }
  if (const auto* v = std::get_if<int64_t>(&it->second)) {
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
  EncodableList list;
  for (const auto& type : DesktopAudioDenoise::Instance().ListDenoiseTypes()) {
    list.push_back(EncodableValue(EncodableMap{
        {EncodableValue("id"), EncodableValue(type.id)},
        {EncodableValue("displayName"), EncodableValue(type.display_name)},
        {EncodableValue("isReady"), EncodableValue(type.is_ready)},
    }));
  }
  return list;
}

EncodableList BuildDiagnosticsList() {
  EncodableList list;
  for (const auto& type : DesktopAudioDenoise::Instance().ListDenoiseTypes()) {
    list.push_back(EncodableValue(EncodableMap{
        {EncodableValue("id"), EncodableValue(type.id)},
        {EncodableValue("displayName"), EncodableValue(type.display_name)},
        {EncodableValue("isReady"), EncodableValue(type.is_ready)},
        {EncodableValue("details"),
         EncodableValue(EncodableMap{
             {EncodableValue("platform"), EncodableValue("windows")},
             {EncodableValue("status"), EncodableValue(type.status)},
         })},
    }));
  }
  return list;
}

EncodableList BuildWarmUpList(const std::string& type_id) {
  EncodableList list;
  for (const auto& entry : DesktopAudioDenoise::Instance().WarmUp(type_id)) {
    list.push_back(EncodableValue(EncodableMap{
        {EncodableValue("id"), EncodableValue(entry.id)},
        {EncodableValue("warmUpOk"), EncodableValue(entry.warm_up_ok)},
        {EncodableValue("warmUpMs"),
         EncodableValue(static_cast<int32_t>(entry.warm_up_ms))},
        {EncodableValue("status"), EncodableValue(entry.status)},
    }));
  }
  return list;
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
  if (method_call.method_name() == "diagnoseDenoise") {
    result->Success(EncodableValue(BuildDiagnosticsList()));
    return;
  }
  if (method_call.method_name() == "warmUpDenoise") {
    result->Success(EncodableValue(BuildWarmUpList(type_id)));
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

    const auto* samples =
        std::get_if<std::vector<float>>(&samples_it->second);
    if (!samples) {
      result->Error("invalid_args", "samples must be a Float32List");
      return;
    }
    std::vector<float> buffer = *samples;
    const auto processed = DesktopAudioDenoise::Instance().ProcessFrame(
        buffer.data(), buffer.size(), channels > 0 ? channels : 1);
    if (!processed.success) {
      result->Error(processed.error_code, processed.error_message);
      return;
    }

    EncodableMap response;
    response[EncodableValue("vad")] = EncodableValue(processed.float_value);
    response[EncodableValue("samples")] = EncodableValue(std::move(buffer));
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
