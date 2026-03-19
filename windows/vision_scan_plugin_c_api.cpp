#include "include/vision_scan/vision_scan_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "vision_scan_plugin.h"

void VisionScanPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  vision_scan::VisionScanPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
