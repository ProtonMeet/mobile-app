#include "include/proton_video_effects/proton_video_effects_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <dlfcn.h>
#include <cstring>
#include <string>

#include "../common/desktop/desktop_background_blur.h"

#define PROTON_VIDEO_EFFECTS_CHANNEL "me.proton.meet/video_effects"

#define PROTON_VIDEO_EFFECTS_PLUGIN(obj)                                         \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), proton_video_effects_plugin_get_type(), \
                               ProtonVideoEffectsPlugin))

struct _ProtonVideoEffectsPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(ProtonVideoEffectsPlugin, proton_video_effects_plugin, g_object_get_type())

static FlValue* LookupArg(FlValue* args, const char* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return nullptr;
  return fl_value_lookup_string(args, key);
}

static std::string GetStringArg(FlValue* args, const char* key) {
  FlValue* value = LookupArg(args, key);
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) return {};
  return fl_value_get_string(value);
}

static double GetDoubleArg(FlValue* args, const char* key,
                           double default_value) {
  FlValue* value = LookupArg(args, key);
  if (!value) return default_value;
  // Dart doubles arrive as float; whole numbers may arrive as int.
  switch (fl_value_get_type(value)) {
    case FL_VALUE_TYPE_FLOAT:
      return fl_value_get_float(value);
    case FL_VALUE_TYPE_INT:
      return static_cast<double>(fl_value_get_int(value));
    default:
      return default_value;
  }
}

static meet_video_effects::DesktopBlurConfig ParseBlurConfig(FlValue* args) {
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

static meet_video_effects::DesktopReplacementRequest ParseReplacementRequest(
    FlValue* args) {
  meet_video_effects::DesktopReplacementRequest request;
  request.mode_is_blur = GetStringArg(args, "backgroundMode") == "blur";
  if (request.mode_is_blur) {
    return request;
  }
  request.path = GetStringArg(args, "replacementImagePath");
  if (request.path.empty()) {
    request.path = GetStringArg(args, "filePath");
  }
  if (!request.path.empty()) {
    return request;
  }
  FlValue* bytes = LookupArg(args, "imageBytes");
  if (bytes && fl_value_get_type(bytes) == FL_VALUE_TYPE_UINT8_LIST) {
    const uint8_t* data = fl_value_get_uint8_list(bytes);
    const size_t length = fl_value_get_length(bytes);
    request.bytes.assign(data, data + length);
  }
  return request;
}

static FlMethodResponse* SegmentationModelResponse(
    const meet_video_effects::DesktopSegmentationModelInfo& info) {
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "model",
                           fl_value_new_string(info.model.c_str()));
  fl_value_set_string_take(map, "backend",
                           fl_value_new_string(info.backend.c_str()));
  fl_value_set_string_take(map, "forced", fl_value_new_bool(info.forced));
  fl_value_set_string_take(map, "supported", fl_value_new_bool(info.supported));
  fl_value_set_string_take(map, "reason",
                           fl_value_new_string(info.reason.c_str()));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

static void HandleMethodCall(ProtonVideoEffectsPlugin* self,
                             FlMethodCall* method_call) {
  (void)self;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  const std::string track_id = GetStringArg(args, "trackId");
  auto& blur = meet_video_effects::DesktopBackgroundBlur::Instance();

  g_autoptr(FlMethodResponse) response = nullptr;

  // Config and model methods are accepted rather than reported as
  // NOT_IMPLEMENTED: Dart rethrows PlatformException for them, which would
  // surface as an error for settings the desktop engine simply ignores.
  if (strcmp(method, "setBackgroundBlurConfig") == 0) {
    blur.SetConfig(ParseBlurConfig(args));
    blur.ApplyReplacementRequest(ParseReplacementRequest(args));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (strcmp(method, "setSegmentationModel") == 0) {
    blur.SetSegmentationModel(GetStringArg(args, "model"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (strcmp(method, "getSegmentationModel") == 0) {
    response = SegmentationModelResponse(blur.SegmentationModelInfo());
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (strcmp(method, "setReplacementBackgroundImage") == 0) {
    if (blur.ApplyReplacementRequest(ParseReplacementRequest(args))) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "IMAGE", "Failed to decode replacement image", nullptr));
    }
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (strcmp(method, "clearReplacementBackground") == 0) {
    blur.ClearReplacementImage();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // attach/detach also carry config args; apply them before attaching.
  if (strcmp(method, "attach") == 0 ||
      strcmp(method, "attachBackgroundBlur") == 0) {
    blur.SetConfig(ParseBlurConfig(args));
    blur.ApplyReplacementRequest(ParseReplacementRequest(args));
  }

  const auto result = blur.Handle(method, track_id);

  if (!result.success) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        result.error_code.c_str(), result.error_message.c_str(), nullptr));
  } else if (result.has_string_value) {
    g_autoptr(FlValue) val = fl_value_new_string(result.string_value.c_str());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (result.has_bool_value) {
    g_autoptr(FlValue) val = fl_value_new_bool(result.bool_value);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void proton_video_effects_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(proton_video_effects_plugin_parent_class)->dispose(object);
}

static void proton_video_effects_plugin_class_init(ProtonVideoEffectsPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = proton_video_effects_plugin_dispose;
}

static void proton_video_effects_plugin_init(ProtonVideoEffectsPlugin* self) {
  (void)self;
}

void proton_video_effects_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  ProtonVideoEffectsPlugin* plugin = PROTON_VIDEO_EFFECTS_PLUGIN(
      g_object_new(proton_video_effects_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      PROTON_VIDEO_EFFECTS_CHANNEL,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, [](FlMethodChannel* /*channel*/, FlMethodCall* method_call,
                  gpointer user_data) {
        HandleMethodCall(PROTON_VIDEO_EFFECTS_PLUGIN(user_data), method_call);
      },
      g_object_ref(plugin),
      g_object_unref);

  Dl_info info;
  if (dladdr(reinterpret_cast<void*>(&proton_video_effects_plugin_register_with_registrar),
             &info) &&
      info.dli_fname) {
    std::string dir(info.dli_fname);
    const auto pos = dir.find_last_of('/');
    if (pos != std::string::npos) {
      dir.resize(pos);
      meet_video_effects::DesktopBackgroundBlur::Instance().SetModelsDirectory(dir);
    }
  }

  g_object_unref(plugin);
}
