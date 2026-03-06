plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localAssetsDir = file("../../../assets")

val mediaKitJars = mapOf(
    "arm64-v8a" to "full-arm64-v8a.jar",
    "armeabi-v7a" to "full-armeabi-v7a.jar",
    "x86" to "full-x86.jar",
    "x86_64" to "full-x86_64.jar"
)

val jniLibsDir = file("${projectDir}/src/main/jniLibs")

fun setupMediaKitLocalJars() {
    val pubCacheHostedDir = if (System.getProperty("os.name").lowercase().contains("win")) {
        file(System.getenv("LOCALAPPDATA") + "/Pub/Cache/hosted")
    } else {
        file(System.getProperty("user.home") + "/.pub-cache/hosted")
    }
    
    val mediaKitPluginDirs = if (pubCacheHostedDir.exists()) {
        pubCacheHostedDir.listFiles()
            ?.filter { it.isDirectory }
            ?.flatMap { hostDir ->
                hostDir.listFiles()
                    ?.filter { it.isDirectory && it.name.startsWith("media_kit_libs_android_video-") }
                    ?: emptyList()
            } ?: emptyList()
    } else {
        emptyList()
    }
    
    if (mediaKitPluginDirs.isEmpty()) {
        println("[media_kit] Plugin not found in pub cache")
        return
    }
    
    val jarFiles = listOf(
        "full-arm64-v8a.jar",
        "full-armeabi-v7a.jar",
        "full-x86.jar",
        "full-x86_64.jar"
    )
    
    val allLocalFilesExist = jarFiles.all { file("${localAssetsDir}/${it}").exists() }
    if (!allLocalFilesExist) {
        println("[media_kit] Local JAR files not found in ${localAssetsDir.absolutePath}")
        return
    }
    
    println("[media_kit] Using local JAR files from ${localAssetsDir.absolutePath}")
    
    mediaKitPluginDirs.forEach { pluginDir ->
        val pluginBuildGradle = file("${pluginDir}/android/build.gradle")
        
        if (pluginBuildGradle.exists()) {
            val content = pluginBuildGradle.readText()
            
            if (!content.contains("// ROCKZERO_PATCHED_V3")) {
                println("[media_kit] Patching plugin build.gradle in ${pluginDir.name}...")
                
                val localPath = localAssetsDir.absolutePath.replace("\\", "/")
                
                val newBuildGradle = """
// ROCKZERO_PATCHED_V3 — libmpv v1.1.11 full variant, auto-patched by build.gradle.kts
import java.io.File
import java.nio.file.Files

group 'com.alexmercerind.media_kit_libs_android_video'
version '1.0'

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.13.0'
    }
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply plugin: 'com.android.library'

android {
    if (project.android.hasProperty("namespace")) {
        namespace 'com.alexmercerind.media_kit_libs_android_video'
    }
    compileSdkVersion 36
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
    defaultConfig {
        minSdkVersion 16
    }
    dependencies {
        implementation fileTree(dir: "${'$'}buildDir/output", include: "*.jar")
    }
}

task downloadDependencies {
    doFirst {
        def localAssetsPath = "$localPath"
        def outputDir = file("${'$'}buildDir/output")
        
        if (!outputDir.exists()) {
            outputDir.mkdirs()
        }
        
        def jarFiles = [
            "full-arm64-v8a.jar",
            "full-armeabi-v7a.jar",
            "full-x86.jar",
            "full-x86_64.jar"
        ]
        
        println "=== media_kit: Using local JAR files ==="
        println "Source: ${'$'}localAssetsPath"
        println "Target: ${'$'}outputDir"
        
        jarFiles.each { jarName ->
            def sourceFile = new File(localAssetsPath, jarName)
            def destFile = new File(outputDir, jarName)
            
            if (sourceFile.exists()) {
                if (!destFile.exists() || sourceFile.lastModified() > destFile.lastModified()) {
                    Files.copy(sourceFile.toPath(), destFile.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING)
                    println "  [COPIED] ${'$'}jarName"
                } else {
                    println "  [SKIPPED] ${'$'}jarName (up-to-date)"
                }
            } else {
                println "  [MISSING] ${'$'}jarName"
            }
        }
        println "=== Done ==="
    }
}

assemble.dependsOn(downloadDependencies)
"""
                
                pluginBuildGradle.writeText(newBuildGradle)
                println("[media_kit] Plugin patched successfully: ${pluginDir.name}")
            } else {
                println("[media_kit] Plugin already patched (v3): ${pluginDir.name}")
            }
        }
    }
}

// 在配置阶段立即执行
setupMediaKitLocalJars()

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
        applicationId = "com.blue.rockzero"
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
