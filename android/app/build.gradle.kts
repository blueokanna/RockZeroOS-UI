plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ============================================================================
// media_kit 本地库配置
// 从本地 assets 目录加载 JAR 包，避免从 GitHub 下载失败
// ============================================================================

// 本地 assets 目录路径（包含 media_kit JAR 包）
val localAssetsDir = file("D:/RustProject/RockZeroOS-Service/assets")

// media_kit JAR 文件映射
val mediaKitJars = mapOf(
    "arm64-v8a" to "full-arm64-v8a.jar",
    "armeabi-v7a" to "full-armeabi-v7a.jar",
    "x86" to "full-x86.jar",
    "x86_64" to "full-x86_64.jar"
)

// 复制本地 JAR 到 libs 目录的任务
tasks.register("copyMediaKitLibs") {
    doLast {
        val libsDir = file("${projectDir}/libs")
        if (!libsDir.exists()) {
            libsDir.mkdirs()
        }
        
        mediaKitJars.forEach { (arch, jarName) ->
            val sourceFile = file("${localAssetsDir}/${jarName}")
            val destFile = file("${libsDir}/${jarName}")
            
            if (sourceFile.exists()) {
                if (!destFile.exists() || sourceFile.lastModified() > destFile.lastModified()) {
                    sourceFile.copyTo(destFile, overwrite = true)
                    println("Copied media_kit library: ${jarName}")
                } else {
                    println("media_kit library already up-to-date: ${jarName}")
                }
            } else {
                println("WARNING: media_kit library not found: ${sourceFile.absolutePath}")
            }
        }
    }
}

// 确保在构建前复制库文件
tasks.named("preBuild") {
    dependsOn("copyMediaKitLibs")
}

android {
    namespace = "com.example.rockzero"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.rockzero"
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
    
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("libs")
        }
    }
    
    // 打包选项：排除重复文件
    packaging {
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/ASL2.0",
                "META-INF/*.kotlin_module"
            )
        }
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 本地 media_kit JAR 库
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
    
    // Biometric Authentication
    implementation("androidx.biometric:biometric:1.2.0-alpha05")
    
    // FIDO2/Passkey Support
    implementation("com.google.android.gms:play-services-fido:21.1.0")
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
    
    // Material Design 3 Dynamic Color
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.core:core-ktx:1.15.0")
    
    // Coroutines for async operations
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.8.1")
}
