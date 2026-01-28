import Flutter
import UIKit
import AuthenticationServices
import LocalAuthentication

/// FIDO2/WebAuthn 插件
/// 
/// 支持 Passkey 和平台认证器（Face ID/Touch ID）
@available(iOS 15.0, *)
public class Fido2Plugin: NSObject, FlutterPlugin, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    private var pendingResult: FlutterResult?
    private var pendingOperation: String?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "rockzero/fido2", binaryMessenger: registrar.messenger())
        let instance = Fido2Plugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(isAvailable())
        case "isPlatformAuthenticatorAvailable":
            result(isPlatformAuthenticatorAvailable())
        case "createCredential":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing arguments", details: nil))
                return
            }
            createCredential(args: args, result: result)
        case "getAssertion":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing arguments", details: nil))
                return
            }
            getAssertion(args: args, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Availability Checks
    
    private func isAvailable() -> Bool {
        if #available(iOS 16.0, *) {
            return true
        }
        return false
    }
    
    private func isPlatformAuthenticatorAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    // MARK: - Credential Creation (Registration)
    
    private func createCredential(args: [String: Any], result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(FlutterError(code: "UNSUPPORTED", message: "iOS 16.0 or later required", details: nil))
            return
        }
        
        guard let challenge = args["challenge"] as? String,
              let rpId = args["rpId"] as? String,
              let userId = args["userId"] as? String,
              let userName = args["userName"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing required arguments", details: nil))
            return
        }
        
        let userDisplayName = args["userDisplayName"] as? String ?? userName
        
        // 解码 challenge
        guard let challengeData = Data(base64Encoded: challenge, options: .ignoreUnknownCharacters) else {
            result(FlutterError(code: "INVALID_CHALLENGE", message: "Invalid challenge format", details: nil))
            return
        }
        
        // 创建用户 ID
        guard let userIdData = userId.data(using: .utf8) else {
            result(FlutterError(code: "INVALID_USER_ID", message: "Invalid user ID", details: nil))
            return
        }
        
        // 创建 Passkey 注册请求
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        
        let registrationRequest = publicKeyCredentialProvider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: userName,
            userID: userIdData
        )
        
        // 设置用户显示名称
        registrationRequest.displayName = userDisplayName
        
        // 设置用户验证偏好
        if let userVerification = args["userVerification"] as? String {
            switch userVerification {
            case "required":
                registrationRequest.userVerificationPreference = .required
            case "preferred":
                registrationRequest.userVerificationPreference = .preferred
            case "discouraged":
                registrationRequest.userVerificationPreference = .discouraged
            default:
                registrationRequest.userVerificationPreference = .preferred
            }
        }
        
        // 执行注册
        let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
        authController.delegate = self
        authController.presentationContextProvider = self
        
        pendingResult = result
        pendingOperation = "register"
        
        authController.performRequests()
    }
    
    // MARK: - Assertion (Authentication)
    
    private func getAssertion(args: [String: Any], result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(FlutterError(code: "UNSUPPORTED", message: "iOS 16.0 or later required", details: nil))
            return
        }
        
        guard let challenge = args["challenge"] as? String,
              let rpId = args["rpId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing required arguments", details: nil))
            return
        }
        
        // 解码 challenge
        guard let challengeData = Data(base64Encoded: challenge, options: .ignoreUnknownCharacters) else {
            result(FlutterError(code: "INVALID_CHALLENGE", message: "Invalid challenge format", details: nil))
            return
        }
        
        // 创建 Passkey 认证请求
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        
        let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challengeData)
        
        // 设置允许的凭证
        if let allowCredentials = args["allowCredentials"] as? [String] {
            var credentialDescriptors: [ASAuthorizationPlatformPublicKeyCredentialDescriptor] = []
            for credId in allowCredentials {
                if let credIdData = Data(base64Encoded: credId, options: .ignoreUnknownCharacters) {
                    let descriptor = ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: credIdData)
                    credentialDescriptors.append(descriptor)
                }
            }
            if !credentialDescriptors.isEmpty {
                assertionRequest.allowedCredentials = credentialDescriptors
            }
        }
        
        // 设置用户验证偏好
        if let userVerification = args["userVerification"] as? String {
            switch userVerification {
            case "required":
                assertionRequest.userVerificationPreference = .required
            case "preferred":
                assertionRequest.userVerificationPreference = .preferred
            case "discouraged":
                assertionRequest.userVerificationPreference = .discouraged
            default:
                assertionRequest.userVerificationPreference = .preferred
            }
        }
        
        // 执行认证
        let authController = ASAuthorizationController(authorizationRequests: [assertionRequest])
        authController.delegate = self
        authController.presentationContextProvider = self
        
        pendingResult = result
        pendingOperation = "authenticate"
        
        authController.performRequests()
    }
    
    // MARK: - ASAuthorizationControllerDelegate
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let result = pendingResult else { return }
        
        if #available(iOS 16.0, *) {
            if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
                // 注册成功
                let response: [String: Any?] = [
                    "credentialId": credential.credentialID.base64EncodedString(),
                    "clientDataJson": credential.rawClientDataJSON.base64EncodedString(),
                    "attestationObject": credential.rawAttestationObject?.base64EncodedString()
                ]
                result(response)
            } else if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                // 认证成功
                let response: [String: Any?] = [
                    "credentialId": credential.credentialID.base64EncodedString(),
                    "clientDataJson": credential.rawClientDataJSON.base64EncodedString(),
                    "authenticatorData": credential.rawAuthenticatorData.base64EncodedString(),
                    "signature": credential.signature.base64EncodedString(),
                    "userHandle": credential.userID.base64EncodedString()
                ]
                result(response)
            } else {
                result(FlutterError(code: "UNKNOWN_CREDENTIAL", message: "Unknown credential type", details: nil))
            }
        } else {
            result(FlutterError(code: "UNSUPPORTED", message: "iOS 16.0 or later required", details: nil))
        }
        
        pendingResult = nil
        pendingOperation = nil
    }
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let result = pendingResult else { return }
        
        let nsError = error as NSError
        
        if nsError.domain == ASAuthorizationError.errorDomain {
            switch nsError.code {
            case ASAuthorizationError.canceled.rawValue:
                result(FlutterError(code: "CANCELLED", message: "User cancelled", details: nil))
            case ASAuthorizationError.failed.rawValue:
                result(FlutterError(code: "FAILED", message: "Authorization failed", details: error.localizedDescription))
            case ASAuthorizationError.invalidResponse.rawValue:
                result(FlutterError(code: "INVALID_RESPONSE", message: "Invalid response", details: error.localizedDescription))
            case ASAuthorizationError.notHandled.rawValue:
                result(FlutterError(code: "NOT_HANDLED", message: "Request not handled", details: error.localizedDescription))
            case ASAuthorizationError.notInteractive.rawValue:
                result(FlutterError(code: "NOT_INTERACTIVE", message: "Not interactive", details: error.localizedDescription))
            default:
                result(FlutterError(code: "UNKNOWN_ERROR", message: error.localizedDescription, details: nil))
            }
        } else {
            result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil))
        }
        
        pendingResult = nil
        pendingOperation = nil
    }
    
    // MARK: - ASAuthorizationControllerPresentationContextProviding
    
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return UIApplication.shared.windows.first!
        }
        return window
    }
}

/// FIDO2 插件包装器（用于 iOS 15 以下版本的兼容性）
public class Fido2PluginWrapper: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        if #available(iOS 15.0, *) {
            Fido2Plugin.register(with: registrar)
        } else {
            // iOS 15 以下版本，注册一个返回不支持的插件
            let channel = FlutterMethodChannel(name: "rockzero/fido2", binaryMessenger: registrar.messenger())
            let instance = Fido2PluginWrapper()
            registrar.addMethodCallDelegate(instance, channel: channel)
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable", "isPlatformAuthenticatorAvailable":
            result(false)
        default:
            result(FlutterError(code: "UNSUPPORTED", message: "FIDO2 requires iOS 15.0 or later", details: nil))
        }
    }
}
