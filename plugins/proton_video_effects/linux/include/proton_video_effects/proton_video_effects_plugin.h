#ifndef FLUTTER_PLUGIN_PROTON_VIDEO_EFFECTS_PLUGIN_H_
#define FLUTTER_PLUGIN_PROTON_VIDEO_EFFECTS_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _ProtonVideoEffectsPlugin ProtonVideoEffectsPlugin;
typedef struct {
  GObjectClass parent_class;
} ProtonVideoEffectsPluginClass;

FLUTTER_PLUGIN_EXPORT GType proton_video_effects_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void proton_video_effects_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_PROTON_VIDEO_EFFECTS_PLUGIN_H_
