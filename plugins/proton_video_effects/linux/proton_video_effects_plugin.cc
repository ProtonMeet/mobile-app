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

static std::string GetTrackIdFromArgs(FlValue* args) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return {};
  const size_t n = fl_value_get_length(args);
  for (size_t i = 0; i < n; ++i) {
    FlValue* key = fl_value_get_map_key(args, i);
    FlValue* val = fl_value_get_map_value(args, i);
    if (fl_value_get_type(key) == FL_VALUE_TYPE_STRING &&
        fl_value_get_type(val) == FL_VALUE_TYPE_STRING &&
        strcmp(fl_value_get_string(key), "trackId") == 0) {
      return fl_value_get_string(val);
    }
  }
  return {};
}

static void HandleMethodCall(ProtonVideoEffectsPlugin* self,
                             FlMethodCall* method_call) {
  (void)self;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  const std::string track_id = GetTrackIdFromArgs(args);

  const auto result =
      meet_video_effects::DesktopBackgroundBlur::Instance().Handle(method, track_id);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (!result.success) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        result.error_code.c_str(), result.error_message.c_str(), nullptr));
  } else if (strcmp(method, "isImplementationReady") == 0 ||
             strcmp(method, "isBackgroundBlurReady") == 0) {
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
