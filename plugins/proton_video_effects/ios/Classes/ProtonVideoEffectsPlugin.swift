import Flutter
import UIKit

public class ProtonVideoEffectsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    MeetBackgroundBlurNative.register(with: registrar.messenger())
  }
}
