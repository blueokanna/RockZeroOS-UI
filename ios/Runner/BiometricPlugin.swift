import Flutter
import UIKit
import LocalAuthentication

public class BiometricPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "rockzero/biometric", binaryMessenger: registrar.messenger())
        let instance = BiometricPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(isAvailable())
        case "canAuthenticate":
            result(canAuthenticate())
        case "getAvailableBiometrics":
            result(getAvailableBiometrics())
        case "authenticate":
            guard let args = call.arguments as? [String: Any],
                  let reason = args["reason"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing reason", details: nil))
                return
            }
            let biometricOnly = args["biometricOnly"] as? Bool ?? false
            authenticate(reason: reason, biometricOnly: biometricOnly, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func isAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    private func canAuthenticate() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    
    private func getAvailableBiometrics() -> [String] {
        var biometrics: [String] = []
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            if #available(iOS 11.0, *) {
                switch context.biometryType {
                case .faceID:
                    biometrics.append("face")
                case .touchID:
                    biometrics.append("fingerprint")
                case .none:
                    break
                @unknown default:
                    break
                }
            } else {
                // iOS 10 and below only support Touch ID
                biometrics.append("fingerprint")
            }
        }
        
        return biometrics
    }
    
    private func authenticate(reason: String, biometricOnly: Bool, result: @escaping FlutterResult) {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        
        let policy: LAPolicy = biometricOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        
        context.evaluatePolicy(policy, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    result(true)
                } else {
                    if let error = error as? LAError {
                        switch error.code {
                        case .userCancel, .userFallback, .systemCancel, .appCancel:
                            result(false)
                        default:
                            result(FlutterError(code: "AUTH_ERROR", message: error.localizedDescription, details: nil))
                        }
                    } else {
                        result(false)
                    }
                }
            }
        }
    }
}
