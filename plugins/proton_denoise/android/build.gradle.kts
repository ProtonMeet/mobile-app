import com.android.build.gradle.AppExtension
import org.gradle.api.artifacts.VersionCatalogsExtension

group = "com.proton.proton_denoise"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

// Native CMake/Ninja state (FetchContent, RNNoise objects). Must not live under this
// module's Gradle build/ dir (AGP rejects that); use the host app's build/ tree instead.
val protonDenoiseCxxStaging =
    rootProject.layout.buildDirectory.dir("native/proton_denoise/cxx")

/// Same NDK as the host app (Meet: `libs.versions.ndkVersion` / CI `ndk.dir`), not
/// `flutter.ndkVersion` from local.properties (older Flutter default → CXX1104).
fun resolveHostNdkVersion(): String? {
    try {
        val catalog = rootProject.extensions.getByType(VersionCatalogsExtension::class.java)
        val version = catalog.named("libs").findVersion("ndkVersion").orElse(null)?.requiredVersion
        if (!version.isNullOrBlank()) {
            return version
        }
    } catch (_: Exception) {
    }
    return try {
        rootProject.project(":app").extensions.getByType(AppExtension::class.java).ndkVersion
    } catch (_: Exception) {
        null
    }
}

android {
    namespace = "com.proton.proton_denoise"

    compileSdk = 36

    resolveHostNdkVersion()?.let { ndkVersion = it }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
        // Do not set abiFilters here — AGP builds one libproton_denoise.so per ABI and the
        // host app (e.g. Meet) decides which slices go into the universal APK/AAB.
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    // Required for 16 KB page devices (Play / Android 15+).
                    "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON",
                )
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            buildStagingDirectory = protonDenoiseCxxStaging.get().asFile
        }
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

dependencies {
    compileOnly(project(":flutter_webrtc"))
    // WebRTC SDK types referenced by AudioProcessingAdapter (ExternalAudioProcessingFactory).
    compileOnly("io.github.webrtc-sdk:android:144.7559.01")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
