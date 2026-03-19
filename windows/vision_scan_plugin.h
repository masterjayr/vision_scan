#ifndef FLUTTER_PLUGIN_VISION_SCAN_PLUGIN_H_
#define FLUTTER_PLUGIN_VISION_SCAN_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace vision_scan {

class VisionScanPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  VisionScanPlugin();

  virtual ~VisionScanPlugin();

  // Disallow copy and assign.
  VisionScanPlugin(const VisionScanPlugin&) = delete;
  VisionScanPlugin& operator=(const VisionScanPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace vision_scan

#endif  // FLUTTER_PLUGIN_VISION_SCAN_PLUGIN_H_
