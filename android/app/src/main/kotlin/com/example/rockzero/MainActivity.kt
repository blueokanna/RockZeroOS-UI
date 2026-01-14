package com.example.rockzero

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Bundle
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.google.android.gms.fido.Fido
import com.google.android.gms.fido.fido2.api.common.*
import com.google.android.material.color.DynamicColors
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.util.concurrent.Executor
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class MainActivity : FlutterFragmentActivity() {
    private val BIOMETRIC_CHANNEL = "rockzero/biometric"
    private val FIDO2_CHANNEL = "rockzero/fido2"
    private val SYSTEM_COLORS_CHANNEL = "rockzero/system_colors"
    private val VIDEO_OPTIMIZER_CHANNEL = "rockzero/video_optimizer"
    
    private lateinit var biometricExecutor: Executor
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    
    override fun onCreate(savedInstanceState: Bundle?) {
        // Apply dynamic colors before super.onCreate
        DynamicColors.applyToActivityIfAvailable(this)
        super.onCreate(savedInstanceState)
        biometricExecutor = ContextCompat.getMainExecutor(this)
        
        // Log video codec capabilities for debugging
        VideoPlayerOptimizer.logAllCodecs()
        val capabilities = VideoPlayerOptimizer.getDeviceCapabilities(this)
        android.util.Log.d("MainActivity", "Video capabilities: $capabilities")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Biometric Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BIOMETRIC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> handleBiometricAvailable(result)
                    "canAuthenticate" -> handleCanAuthenticate(result)
                    "getAvailableBiometrics" -> handleGetAvailableBiometrics(result)
                    "authenticate" -> handleAuthenticate(call, result)
                    else -> result.notImplemented()
                }
            }
        
        // FIDO2 Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FIDO2_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> handleFido2Available(result)
                    "isPlatformAuthenticatorAvailable" -> handlePlatformAuthenticatorAvailable(result)
                    "createCredential" -> handleCreateCredential(call, result)
                    "getAssertion" -> handleGetAssertion(call, result)
                    else -> result.notImplemented()
                }
            }
        
        // System Colors Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_COLORS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAccentColor" -> handleGetAccentColor(result)
                    "isDynamicColorAvailable" -> handleIsDynamicColorAvailable(result)
                    "getSystemColors" -> handleGetSystemColors(result)
                    else -> result.notImplemented()
                }
            }
        
        // Video Optimizer Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIDEO_OPTIMIZER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceCapabilities" -> {
                        val capabilities = VideoPlayerOptimizer.getDeviceCapabilities(this)
                        result.success(capabilities)
                    }
                    "isDtsSupported" -> {
                        result.success(VideoPlayerOptimizer.isDtsSupported())
                    }
                    "isAc3Supported" -> {
                        result.success(VideoPlayerOptimizer.isAc3Supported())
                    }
                    "getSupportedAudioCodecs" -> {
                        result.success(VideoPlayerOptimizer.getSupportedAudioCodecs())
                    }
                    else -> result.notImplemented()
                }
            }
    }
    
    // ============ Biometric Methods ============
    
    private fun handleBiometricAvailable(result: MethodChannel.Result) {
        val biometricManager = BiometricManager.from(this)
        val canAuth = biometricManager.canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
            BiometricManager.Authenticators.BIOMETRIC_WEAK
        )
        result.success(canAuth == BiometricManager.BIOMETRIC_SUCCESS)
    }
    
    private fun handleCanAuthenticate(result: MethodChannel.Result) {
        val biometricManager = BiometricManager.from(this)
        val canAuth = biometricManager.canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL
        )
        result.success(canAuth == BiometricManager.BIOMETRIC_SUCCESS)
    }
    
    private fun handleGetAvailableBiometrics(result: MethodChannel.Result) {
        val biometricManager = BiometricManager.from(this)
        val types = mutableListOf<String>()
        
        // Check for strong biometrics (fingerprint, face, iris)
        if (biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) 
            == BiometricManager.BIOMETRIC_SUCCESS) {
            types.add("strong")
            // On most devices, strong biometric is fingerprint
            types.add("fingerprint")
        }
        
        // Check for weak biometrics
        if (biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) 
            == BiometricManager.BIOMETRIC_SUCCESS) {
            if (!types.contains("weak")) types.add("weak")
        }
        
        // Check for face unlock on supported devices
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val pm = packageManager
            if (pm.hasSystemFeature("android.hardware.biometrics.face")) {
                types.add("face")
            }
            if (pm.hasSystemFeature("android.hardware.biometrics.iris")) {
                types.add("iris")
            }
        }
        
        result.success(types)
    }
    
    private fun handleAuthenticate(call: MethodCall, result: MethodChannel.Result) {
        val reason = call.argument<String>("reason") ?: "Please authenticate"
        val biometricOnly = call.argument<Boolean>("biometricOnly") ?: false
        
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("RockZero Authentication")
            .setSubtitle(reason)
            .apply {
                if (biometricOnly) {
                    setNegativeButtonText("Cancel")
                    setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                } else {
                    setAllowedAuthenticators(
                        BiometricManager.Authenticators.BIOMETRIC_STRONG or
                        BiometricManager.Authenticators.BIOMETRIC_WEAK or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    )
                }
            }
            .build()
        
        val biometricPrompt = BiometricPrompt(this, biometricExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                    super.onAuthenticationSucceeded(authResult)
                    result.success(true)
                }
                
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    super.onAuthenticationError(errorCode, errString)
                    result.success(false)
                }
                
                override fun onAuthenticationFailed() {
                    super.onAuthenticationFailed()
                    // Don't return false here, let user retry
                }
            })
        
        biometricPrompt.authenticate(promptInfo)
    }
    
    // ============ FIDO2 Methods ============
    
    private fun handleFido2Available(result: MethodChannel.Result) {
        try {
            val fido2Client = Fido.getFido2ApiClient(this)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }
    
    private fun handlePlatformAuthenticatorAvailable(result: MethodChannel.Result) {
        scope.launch {
            try {
                val fido2Client = Fido.getFido2ApiClient(this@MainActivity)
                val task = fido2Client.isUserVerifyingPlatformAuthenticatorAvailable
                val isAvailable = suspendCoroutine<Boolean> { cont ->
                    task.addOnSuccessListener { cont.resume(it) }
                    task.addOnFailureListener { cont.resume(false) }
                }
                result.success(isAvailable)
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }
    
    private fun handleCreateCredential(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val challenge = call.argument<String>("challenge") ?: ""
                val rpId = call.argument<String>("rpId") ?: ""
                val rpName = call.argument<String>("rpName") ?: ""
                val userId = call.argument<String>("userId") ?: ""
                val userName = call.argument<String>("userName") ?: ""
                val userDisplayName = call.argument<String>("userDisplayName") ?: ""
                val authenticatorAttachment = call.argument<String>("authenticatorAttachment") ?: "platform"
                val requireResidentKey = call.argument<Boolean>("requireResidentKey") ?: false
                val userVerification = call.argument<String>("userVerification") ?: "preferred"
                
                val options = PublicKeyCredentialCreationOptions.Builder()
                    .setRp(PublicKeyCredentialRpEntity(rpId, rpName, null))
                    .setUser(PublicKeyCredentialUserEntity(
                        userId.toByteArray(),
                        userName,
                        null,
                        userDisplayName
                    ))
                    .setChallenge(android.util.Base64.decode(challenge, android.util.Base64.URL_SAFE))
                    .setParameters(listOf(
                        PublicKeyCredentialParameters(
                            PublicKeyCredentialType.PUBLIC_KEY.toString(),
                            EC2Algorithm.ES256.algoValue
                        ),
                        PublicKeyCredentialParameters(
                            PublicKeyCredentialType.PUBLIC_KEY.toString(),
                            RSAAlgorithm.RS256.algoValue
                        )
                    ))
                    .setTimeoutSeconds(60.0)
                    .setAuthenticatorSelection(
                        AuthenticatorSelectionCriteria.Builder()
                            .setAttachment(
                                if (authenticatorAttachment == "platform") 
                                    Attachment.PLATFORM 
                                else 
                                    Attachment.CROSS_PLATFORM
                            )
                            .setRequireResidentKey(requireResidentKey)
                            .build()
                    )
                    .build()
                
                val fido2Client = Fido.getFido2ApiClient(this@MainActivity)
                val pendingIntent = suspendCoroutine<android.app.PendingIntent?> { cont ->
                    fido2Client.getRegisterPendingIntent(options)
                        .addOnSuccessListener { cont.resume(it) }
                        .addOnFailureListener { cont.resume(null) }
                }
                
                if (pendingIntent != null) {
                    // Store result callback for activity result
                    pendingFido2Result = result
                    pendingFido2Operation = "register"
                    startIntentSenderForResult(
                        pendingIntent.intentSender,
                        FIDO2_REQUEST_CODE,
                        null, 0, 0, 0
                    )
                } else {
                    result.error("FIDO2_ERROR", "Failed to create credential", null)
                }
            } catch (e: Exception) {
                result.error("FIDO2_ERROR", e.message, null)
            }
        }
    }
    
    private fun handleGetAssertion(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val challenge = call.argument<String>("challenge") ?: ""
                val rpId = call.argument<String>("rpId") ?: ""
                val allowCredentials = call.argument<List<String>>("allowCredentials") ?: emptyList()
                val userVerification = call.argument<String>("userVerification") ?: "preferred"
                val timeout = call.argument<Int>("timeout") ?: 60000
                
                val options = PublicKeyCredentialRequestOptions.Builder()
                    .setRpId(rpId)
                    .setChallenge(android.util.Base64.decode(challenge, android.util.Base64.URL_SAFE))
                    .setTimeoutSeconds((timeout / 1000).toDouble())
                    .setAllowList(allowCredentials.map { credId ->
                        PublicKeyCredentialDescriptor(
                            PublicKeyCredentialType.PUBLIC_KEY.toString(),
                            android.util.Base64.decode(credId, android.util.Base64.URL_SAFE),
                            null
                        )
                    })
                    .build()
                
                val fido2Client = Fido.getFido2ApiClient(this@MainActivity)
                val pendingIntent = suspendCoroutine<android.app.PendingIntent?> { cont ->
                    fido2Client.getSignPendingIntent(options)
                        .addOnSuccessListener { cont.resume(it) }
                        .addOnFailureListener { cont.resume(null) }
                }
                
                if (pendingIntent != null) {
                    pendingFido2Result = result
                    pendingFido2Operation = "authenticate"
                    startIntentSenderForResult(
                        pendingIntent.intentSender,
                        FIDO2_REQUEST_CODE,
                        null, 0, 0, 0
                    )
                } else {
                    result.error("FIDO2_ERROR", "Failed to get assertion", null)
                }
            } catch (e: Exception) {
                result.error("FIDO2_ERROR", e.message, null)
            }
        }
    }
    
    // ============ System Colors Methods ============
    
    private fun handleGetAccentColor(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val colorInt = getColor(android.R.color.system_accent1_500)
                result.success(colorInt)
            } catch (e: Exception) {
                result.success(null)
            }
        } else {
            result.success(null)
        }
    }
    
    private fun handleIsDynamicColorAvailable(result: MethodChannel.Result) {
        result.success(DynamicColors.isDynamicColorAvailable())
    }
    
    private fun handleGetSystemColors(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val colors = mapOf(
                    "accent1_0" to getColor(android.R.color.system_accent1_0),
                    "accent1_100" to getColor(android.R.color.system_accent1_100),
                    "accent1_200" to getColor(android.R.color.system_accent1_200),
                    "accent1_300" to getColor(android.R.color.system_accent1_300),
                    "accent1_400" to getColor(android.R.color.system_accent1_400),
                    "accent1_500" to getColor(android.R.color.system_accent1_500),
                    "accent1_600" to getColor(android.R.color.system_accent1_600),
                    "accent1_700" to getColor(android.R.color.system_accent1_700),
                    "accent1_800" to getColor(android.R.color.system_accent1_800),
                    "accent1_900" to getColor(android.R.color.system_accent1_900),
                    "accent1_1000" to getColor(android.R.color.system_accent1_1000),
                    "accent2_500" to getColor(android.R.color.system_accent2_500),
                    "accent3_500" to getColor(android.R.color.system_accent3_500),
                    "neutral1_500" to getColor(android.R.color.system_neutral1_500),
                    "neutral2_500" to getColor(android.R.color.system_neutral2_500)
                )
                result.success(colors)
            } catch (e: Exception) {
                result.success(null)
            }
        } else {
            result.success(null)
        }
    }
    
    // ============ Activity Result Handling ============
    
    private var pendingFido2Result: MethodChannel.Result? = null
    private var pendingFido2Operation: String? = null
    
    companion object {
        private const val FIDO2_REQUEST_CODE = 1001
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == FIDO2_REQUEST_CODE) {
            val result = pendingFido2Result
            val operation = pendingFido2Operation
            pendingFido2Result = null
            pendingFido2Operation = null
            
            if (result == null) return
            
            if (resultCode != Activity.RESULT_OK || data == null) {
                result.error("FIDO2_CANCELLED", "User cancelled or error occurred", null)
                return
            }
            
            try {
                val responseBytes = data.getByteArrayExtra(Fido.FIDO2_KEY_RESPONSE_EXTRA)
                if (responseBytes == null) {
                    result.error("FIDO2_ERROR", "No response data received", null)
                    return
                }
                
                if (operation == "register") {
                    val response = AuthenticatorAttestationResponse.deserializeFromBytes(responseBytes)
                    result.success(mapOf(
                        "credentialId" to android.util.Base64.encodeToString(
                            response.keyHandle, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP
                        ),
                        "clientDataJson" to android.util.Base64.encodeToString(
                            response.clientDataJSON, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP
                        ),
                        "attestationObject" to android.util.Base64.encodeToString(
                            response.attestationObject, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP
                        )
                    ))
                } else if (operation == "authenticate") {
                    val response = AuthenticatorAssertionResponse.deserializeFromBytes(responseBytes)
                    result.success(mapOf(
                        "credentialId" to android.util.Base64.encodeToString(
                            response.keyHandle, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP
                        ),
                        "clientDataJson" to android.util.Base64.encodeToString(
                            response.clientDataJSON, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP
                        ),
                        "authenticatorData" to android.util.Base64.encodeToString(
                            response.authenticatorData, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP
                        ),
                        "signature" to android.util.Base64.encodeToString(
                            response.signature, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP
                        ),
                        "userHandle" to response.userHandle?.let {
                            android.util.Base64.encodeToString(it, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP)
                        }
                    ))
                }
            } catch (e: Exception) {
                result.error("FIDO2_ERROR", e.message, null)
            }
        }
    }
}
