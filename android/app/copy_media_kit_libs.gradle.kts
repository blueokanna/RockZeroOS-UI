// ============================================================================
// media_kit 本地库复制脚本
// 
// 此脚本负责从本地 assets 目录复制 media_kit 的 JAR 包到项目的 libs 目录
// 避免从 GitHub 下载失败的问题
// ============================================================================

import java.io.File

// 本地 assets 目录路径
val localAssetsDir = File("D:/RustProject/RockZeroOS-Service/assets")

// media_kit JAR 文件列表
val mediaKitJars = listOf(
    "full-arm64-v8a.jar",
    "full-armeabi-v7a.jar",
    "full-x86.jar",
    "full-x86_64.jar"
)

// 目标 libs 目录
val libsDir = File(projectDir, "libs")

/**
 * 复制 media_kit 库文件
 */
fun copyMediaKitLibraries() {
    println("=== Copying media_kit libraries ===")
    println("Source directory: ${localAssetsDir.absolutePath}")
    println("Target directory: ${libsDir.absolutePath}")
    
    // 确保目标目录存在
    if (!libsDir.exists()) {
        libsDir.mkdirs()
        println("Created libs directory")
    }
    
    var copiedCount = 0
    var skippedCount = 0
    var missingCount = 0
    
    mediaKitJars.forEach { jarName ->
        val sourceFile = File(localAssetsDir, jarName)
        val destFile = File(libsDir, jarName)
        
        when {
            !sourceFile.exists() -> {
                println("  [MISSING] $jarName - Source file not found")
                missingCount++
            }
            !destFile.exists() || sourceFile.lastModified() > destFile.lastModified() -> {
                sourceFile.copyTo(destFile, overwrite = true)
                println("  [COPIED] $jarName")
                copiedCount++
            }
            else -> {
                println("  [SKIPPED] $jarName - Already up-to-date")
                skippedCount++
            }
        }
    }
    
    println("=== Summary ===")
    println("  Copied: $copiedCount")
    println("  Skipped: $skippedCount")
    println("  Missing: $missingCount")
    
    if (missingCount > 0) {
        println("")
        println("WARNING: Some media_kit JAR files are missing!")
        println("Please ensure the following files exist in: ${localAssetsDir.absolutePath}")
        mediaKitJars.forEach { jarName ->
            val sourceFile = File(localAssetsDir, jarName)
            if (!sourceFile.exists()) {
                println("  - $jarName")
            }
        }
    }
}

// 执行复制
copyMediaKitLibraries()
