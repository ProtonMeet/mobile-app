#include "include/proton_denoise/proton_denoise_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <algorithm>
#include <string>
#include <vector>

#include "../common/desktop/desktop_audio_denoise.h"

#define PROTON_DENOISE_EFFECTS_CHANNEL "me.proton.meet/denoise"
#define PROTON_DENOISE_LEGACY_CHANNEL "proton_denoise"

#define PROTON_DENOISE_PLUGIN(obj)                                         \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), proton_denoise_plugin_get_type(), \
                               ProtonDenoisePlugin))

struct _ProtonDenoisePlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(ProtonDenoisePlugin, proton_denoise_plugin, g_object_get_type())

static std::string GetStringArg(FlValue* args, const char* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return {};
  }
  const size_t n = fl_value_get_length(args);
  for (size_t i = 0; i < n; ++i) {
    FlValue* k = fl_value_get_map_key(args, i);
    FlValue* v = fl_value_get_map_value(args, i);
    if (fl_value_get_type(k) == FL_VALUE_TYPE_STRING &&
        fl_value_get_type(v) == FL_VALUE_TYPE_STRING &&
        strcmp(fl_value_get_string(k), key) == 0) {
      return fl_value_get_string(v);
    }
  }
  return {};
}

static int GetIntArg(FlValue* args, const char* key, int default_value) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return default_value;
  }
  const size_t n = fl_value_get_length(args);
  for (size_t i = 0; i < n; ++i) {
    FlValue* k = fl_value_get_map_key(args, i);
    FlValue* v = fl_value_get_map_value(args, i);
    if (fl_value_get_type(k) == FL_VALUE_TYPE_STRING &&
        strcmp(fl_value_get_string(k), key) == 0 &&
        fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
      return static_cast<int>(fl_value_get_int(v));
    }
  }
  return default_value;
}

static bool ReadFloatSamples(FlValue* samples_val, std::vector<float>* buffer) {
  if (!samples_val || buffer == nullptr) {
    return false;
  }
  const FlValueType type = fl_value_get_type(samples_val);
  if (type == FL_VALUE_TYPE_UINT8_LIST) {
    const uint8_t* bytes = fl_value_get_uint8_list(samples_val);
    const size_t byte_count = fl_value_get_length(samples_val);
    if (byte_count == 0 || byte_count % sizeof(float) != 0) {
      return false;
    }
    buffer->resize(byte_count / sizeof(float));
    auto* dest = reinterpret_cast<uint8_t*>(buffer->data());
    std::copy(bytes, bytes + byte_count, dest);
    return true;
  }
  if (type == FL_VALUE_TYPE_FLOAT_LIST) {
    const size_t count = fl_value_get_length(samples_val);
    const float* src = fl_value_get_float_list(samples_val);
    buffer->assign(src, src + count);
    return true;
  }
  return false;
}

static bool GetBoolArg(FlValue* args, const char* key, bool default_value) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return default_value;
  }
  const size_t n = fl_value_get_length(args);
  for (size_t i = 0; i < n; ++i) {
    FlValue* k = fl_value_get_map_key(args, i);
    FlValue* v = fl_value_get_map_value(args, i);
    if (fl_value_get_type(k) == FL_VALUE_TYPE_STRING &&
        fl_value_get_type(v) == FL_VALUE_TYPE_BOOL &&
        strcmp(fl_value_get_string(k), key) == 0) {
      return fl_value_get_bool(v);
    }
  }
  return default_value;
}

static FlValue* BuildDenoiseTypesList() {
  FlValue* list = fl_value_new_list();
  FlValue* rnnoise = fl_value_new_map();
  fl_value_set_string_take(rnnoise, "id", fl_value_new_string("rnnoise"));
  fl_value_set_string_take(rnnoise, "displayName",
                           fl_value_new_string("RNNoise"));
  fl_value_set_string_take(
      rnnoise, "isReady",
      fl_value_new_bool(proton_denoise::DesktopAudioDenoise::Instance()
                            .IsRnnoiseReady()));
  fl_value_append_take(list, rnnoise);
  FlValue* deepfilter = fl_value_new_map();
  fl_value_set_string_take(deepfilter, "id", fl_value_new_string("deepfilter"));
  fl_value_set_string_take(deepfilter, "displayName",
                           fl_value_new_string("DeepFilter"));
  fl_value_set_string_take(deepfilter, "isReady", fl_value_new_bool(false));
  fl_value_append_take(list, deepfilter);
  return list;
}

static void HandleEffectsCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  const std::string track_id = GetStringArg(args, "trackId");
  const std::string type_id = GetStringArg(args, "type");

  const auto handled = proton_denoise::DesktopAudioDenoise::Instance().Handle(
      PROTON_DENOISE_EFFECTS_CHANNEL, method, track_id, type_id, false);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (!handled.success) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        handled.error_code.c_str(), handled.error_message.c_str(), nullptr));
  } else if (strcmp(method, "listDenoiseTypes") == 0) {
    g_autoptr(FlValue) list = BuildDenoiseTypesList();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else if (strcmp(method, "isTypeReady") == 0) {
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(handled.bool_value)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void HandleLegacyCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  const bool enabled = GetBoolArg(args, "enabled", false);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "processFrame") == 0) {
    const int channels = GetIntArg(args, "channels", 1);
    FlValue* samples_val = nullptr;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      const size_t n = fl_value_get_length(args);
      for (size_t i = 0; i < n; ++i) {
        FlValue* k = fl_value_get_map_key(args, i);
        if (fl_value_get_type(k) == FL_VALUE_TYPE_STRING &&
            strcmp(fl_value_get_string(k), "samples") == 0) {
          samples_val = fl_value_get_map_value(args, i);
          break;
        }
      }
    }
    std::vector<float> buffer;
    if (!ReadFloatSamples(samples_val, &buffer)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid_args", "Missing float samples", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    const auto processed =
        proton_denoise::DesktopAudioDenoise::Instance().ProcessFrame(
            buffer.data(), buffer.size(), channels > 0 ? channels : 1);
    if (!processed.success) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          processed.error_code.c_str(), processed.error_message.c_str(),
          nullptr));
    } else {
      FlValue* map = fl_value_new_map();
      const size_t byte_count = buffer.size() * sizeof(float);
      FlValue* out_bytes = fl_value_new_uint8_list(
          reinterpret_cast<const uint8_t*>(buffer.data()), byte_count);
      fl_value_set_string_take(map, "samples", out_bytes);
      fl_value_set_string_take(map, "vad",
                               fl_value_new_float(processed.float_value));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
    }
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  const auto handled = proton_denoise::DesktopAudioDenoise::Instance().Handle(
      PROTON_DENOISE_LEGACY_CHANNEL, method, {}, {}, enabled);

  if (!handled.success) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        handled.error_code.c_str(), handled.error_message.c_str(), nullptr));
  } else if (strcmp(method, "create") == 0) {
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(handled.bool_value)));
  } else if (strcmp(method, "getFrameSize") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_int(handled.int_value)));
  } else if (strcmp(method, "isEnabled") == 0) {
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(handled.bool_value)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  (void)channel;
  (void)user_data;
  const gchar* name = fl_method_call_get_name(method_call);
  if (strcmp(name, "listDenoiseTypes") == 0 || strcmp(name, "isTypeReady") == 0 ||
      strcmp(name, "attach") == 0 || strcmp(name, "detach") == 0) {
    HandleEffectsCall(method_call);
    return;
  }
  HandleLegacyCall(method_call);
}

static void proton_denoise_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(proton_denoise_plugin_parent_class)->dispose(object);
}

static void proton_denoise_plugin_class_init(ProtonDenoisePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = proton_denoise_plugin_dispose;
}

static void proton_denoise_plugin_init(ProtonDenoisePlugin* self) {
  (void)self;
}

static void register_channel(FlPluginRegistrar* registrar,
                             const char* channel_name) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), channel_name,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
}

void proton_denoise_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  PROTON_DENOISE_PLUGIN(
      g_object_new(proton_denoise_plugin_get_type(), nullptr));
  register_channel(registrar, PROTON_DENOISE_EFFECTS_CHANNEL);
  register_channel(registrar, PROTON_DENOISE_LEGACY_CHANNEL);
}
