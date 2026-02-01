package com.blue.rockzero

import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.util.Log

object VideoPlayerOptimizer {
    private const val TAG = "VideoPlayerOptimizer"

    fun hasHardwareDecoder(mimeType: String): Boolean {
        val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        val codecInfos = codecList.codecInfos

        for (codecInfo in codecInfos) {
            if (codecInfo.isEncoder) continue

            val types = codecInfo.supportedTypes
            for (type in types) {
                if (type.equals(mimeType, ignoreCase = true)) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        if (codecInfo.isHardwareAccelerated) {
                            Log.d(TAG, "Hardware decoder found for $mimeType: ${codecInfo.name}")
                            return true
                        }
                    } else {
                        if (!codecInfo.name.startsWith("OMX.google.")) {
                            Log.d(TAG, "Hardware decoder found for $mimeType: ${codecInfo.name}")
                            return true
                        }
                    }
                }
            }
        }
        Log.d(TAG, "No hardware decoder found for $mimeType")
        return false
    }

    fun getSupportedAudioCodecs(): List<String> {
        val supportedCodecs = mutableListOf<String>()
        val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        val codecInfos = codecList.codecInfos

        for (codecInfo in codecInfos) {
            if (codecInfo.isEncoder) continue

            val types = codecInfo.supportedTypes
            for (type in types) {
                if (type.startsWith("audio/") && !supportedCodecs.contains(type)) {
                    supportedCodecs.add(type)
                    Log.d(TAG, "Supported audio codec: $type (${codecInfo.name})")
                }
            }
        }
        return supportedCodecs
    }

    fun isDtsSupported(): Boolean {
        val dtsCodecs = listOf(
            "audio/vnd.dts",
            "audio/vnd.dts.hd",
            "audio/vnd.dts.hd.ma",
            "audio/x-dts"
        )
        
        for (codec in dtsCodecs) {
            if (hasHardwareDecoder(codec)) {
                Log.d(TAG, "DTS audio codec supported: $codec")
                return true
            }
        }
        
        Log.w(TAG, "DTS audio codec NOT supported - may need software decoding")
        return false
    }

    fun isAc3Supported(): Boolean {
        val ac3Codecs = listOf(
            "audio/ac3",
            "audio/eac3",
            "audio/ac4"
        )
        
        for (codec in ac3Codecs) {
            if (hasHardwareDecoder(codec)) {
                Log.d(TAG, "AC3/Dolby audio codec supported: $codec")
                return true
            }
        }
        
        Log.w(TAG, "AC3/Dolby audio codec NOT supported")
        return false
    }

    fun getDeviceCapabilities(context: Context): Map<String, Any> {
        val capabilities = mutableMapOf<String, Any>()
        
        capabilities["h264_hw"] = hasHardwareDecoder("video/avc")
        capabilities["h265_hw"] = hasHardwareDecoder("video/hevc")
        capabilities["vp9_hw"] = hasHardwareDecoder("video/x-vnd.on2.vp9")
        capabilities["av1_hw"] = hasHardwareDecoder("video/av01")
        
        capabilities["aac_hw"] = hasHardwareDecoder("audio/mp4a-latm")
        capabilities["opus_hw"] = hasHardwareDecoder("audio/opus")
        capabilities["dts_supported"] = isDtsSupported()
        capabilities["ac3_supported"] = isAc3Supported()
        
        capabilities["android_version"] = Build.VERSION.SDK_INT
        capabilities["device_model"] = Build.MODEL
        capabilities["manufacturer"] = Build.MANUFACTURER
        
        Log.d(TAG, "Device capabilities: $capabilities")
        return capabilities
    }

    fun logAllCodecs() {
        val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        val codecInfos = codecList.codecInfos

        Log.d(TAG, "=== Available Media Codecs ===")
        for (codecInfo in codecInfos) {
            val types = codecInfo.supportedTypes
            val isHw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                codecInfo.isHardwareAccelerated
            } else {
                !codecInfo.name.startsWith("OMX.google.")
            }
            
            Log.d(TAG, "${codecInfo.name} (${if (codecInfo.isEncoder) "Encoder" else "Decoder"}, ${if (isHw) "HW" else "SW"})")
            for (type in types) {
                Log.d(TAG, "  - $type")
            }
        }
        Log.d(TAG, "=== End of Codec List ===")
    }
}
