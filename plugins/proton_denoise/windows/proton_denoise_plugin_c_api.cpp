#include "include/proton_denoise/proton_denoise_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "proton_denoise_plugin.h"

void ProtonDenoisePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  proton_denoise::ProtonDenoisePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
