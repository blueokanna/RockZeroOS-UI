plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localAssetsDir = file("D:/RustProject/RockZeroOS-Service/assets")

val mediaKitJars = mapOf(
    "arm64-v8a" to "full-arm64-v8a.jar",
    "armeabi-v7a" to "full-armeabi-v7a.jar",
    "x86" to "full-x86.jar",
    "x86_64" to "full-x86_64.jar"
)

val jniLibsDir = file("${projectDir}/src/main/jniLibs")
tasks.register("extractMediaKitLibs") {
    doLast {
        println("=== Extracting media_kit native libraries ===")
        println("Source directory: ${localAssetsDir.absolutePath}")
        println("Target directory: ${jniLibsDir.absolutePath}")
        
        mediaKitJars.forEach { (arch, jarName) ->
            val sourceJar = file("${localAssetsDir}/${jarName}")
            val targetArchDir = file("${jniLibsDir}/${arch}")
            
            if (!sourceJar.exists()) {
                println("  [MISSING] ${jarName}")
                return@forEach
            }
            
            val markerFile = file("${targetArchDir}/.extracted")
            if (markerFile.exists() && markerFile.lastModified() >= sourceJar.lastModified()) {
                println("  [SKIPPED] ${arch} - Already extracted")
                return@forEach
            }
            
            if (!targetArchDir.exists()) {
                targetArchDir.mkdirs()
            }
            
            println("  [EXTRACTING] ${jarName} -> ${arch}/")
            copy {
                from(zipTree(sourceJar)) {
                    include("**/*.so")
                    eachFile {
                        relativePath = RelativePath(true, name)
                    }
                }
                into(targetArchDir)
                includeEmptyDirs = false
            }
            
            targetArchDir.listFiles()?.filter { it.extension == "so" }?.forEach {
                println("    -> ${it.name}")
            }
            
            markerFile.writeText("Extracted from ${jarName} at ${System.currentTimeMillis()}")
        }
        
        println("=== Extraction complete ===")
    }
}

tasks.named("preBuild") {
    dependsOn("extractMediaKitLibs")
}

android {
    namespace = "com.blue.rockzero"
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
            jniLibs.srcDirs("src/main/jniLibs")
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
