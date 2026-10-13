#include "include/ever_up_to_date/ever_up_to_date_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "ever_up_to_date_plugin.h"

void EverUpToDatePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  ever_up_to_date::EverUpToDatePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
