import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 注册自定义插件
    let controller = window?.rootViewController as? FlutterViewController
    if let registrar = controller?.registrar(forPlugin: "BiometricPlugin") {
      BiometricPlugin.register(with: registrar)
    }
    if let registrar = controller?.registrar(forPlugin: "Fido2Plugin") {
      Fido2PluginWrapper.register(with: registrar)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
