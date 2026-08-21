#include "include/proton_screen_recorder/proton_screen_recorder_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

namespace proton_screen_recorder {
void ProtonScreenRecorderPluginRegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar);
}

void ProtonScreenRecorderPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  proton_screen_recorder::ProtonScreenRecorderPluginRegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
