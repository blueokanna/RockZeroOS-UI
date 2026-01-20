package com.rockzero.os

import android.content.Context
import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class BiometricPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: FragmentActivity? = null
    private var context: Context? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "rockzero/biometric")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isAvailable" -> {
                result.success(isAvailable())
            }
            "canAuthenticate" -> {
                result.success(canAuthenticate())
            }
            "getAvailableBiometrics" -> {
                result.success(getAvailableBiometrics())
            }
            "authenticate" -> {
                val reason = call.argument<String>("reason") ?: "Please authenticate"
                val biometricOnly = call.argument<Boolean>("biometricOnly") ?: false
                authenticate(reason, biometricOnly, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun isAvailable(): Boolean {
        val biometricManager = context?.let { BiometricManager.from(it) } ?: return false
        return when (biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)) {
            BiometricManager.BIOMETRIC_SUCCESS -> true
            else -> false
        }
    }

    private fun canAuthenticate(): Boolean {
        val biometricManager = context?.let { BiometricManager.from(it) } ?: return false
        return when (biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL)) {
            BiometricManager.BIOMETRIC_SUCCESS -> true
            else -> false
        }
    }

    private fun getAvailableBiometrics(): List<String> {
        val biometrics = mutableListOf<String>()
        val biometricManager = context?.let { BiometricManager.from(it) } ?: return biometrics

        when (biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
            BiometricManager.BIOMETRIC_SUCCESS -> {
                biometrics.add("strong")
                // Android doesn't provide a way to distinguish between fingerprint, face, and iris
                // We'll add "fingerprint" as the most common type
                biometrics.add("fingerprint")
            }
        }

        when (biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)) {
            BiometricManager.BIOMETRIC_SUCCESS -> {
                if (!biometrics.contains("weak")) {
                    biometrics.add("weak")
                }
            }
        }

        return biometrics
    }

    private fun authenticate(reason: String, biometricOnly: Boolean, result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        val executor = ContextCompat.getMainExecutor(currentActivity)
        val biometricPrompt = BiometricPrompt(currentActivity, executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    super.onAuthenticationError(errorCode, errString)
                    result.success(false)
                }

                override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                    super.onAuthenticationSucceeded(authResult)
                    result.success(true)
                }

                override fun onAuthenticationFailed() {
                    super.onAuthenticationFailed()
                    result.success(false)
                }
            })

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Authentication Required")
            .setSubtitle(reason)
            .setDescription("Use your biometric credential to continue")

        if (biometricOnly) {
            promptInfo.setNegativeButtonText("Cancel")
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                promptInfo.setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
            } else {
                promptInfo.setDeviceCredentialAllowed(true)
            }
        }

        biometricPrompt.authenticate(promptInfo.build())
    }
}
