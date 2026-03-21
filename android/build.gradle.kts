allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force all subprojects to use Java 17
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            project.extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }

        tasks.matching { it.name.contains("UnitTest", ignoreCase = true) }
            .configureEach {
                enabled = false
            }
    }
}

val flutterBuildDir: Directory = rootProject.layout.projectDirectory.dir("../build")
rootProject.layout.buildDirectory.value(flutterBuildDir)

subprojects {
    val rootPath = rootProject.projectDir.toPath().toAbsolutePath().normalize().toString()
    val subprojectPath = project.projectDir.toPath().toAbsolutePath().normalize().toString()
    if (subprojectPath.startsWith(rootPath, ignoreCase = true)) {
        val localSubprojectBuildDir: Directory = flutterBuildDir.dir(project.name)
        project.layout.buildDirectory.value(localSubprojectBuildDir)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
