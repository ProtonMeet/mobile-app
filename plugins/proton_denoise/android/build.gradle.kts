import com.android.build.gradle.AppExtension
import org.gradle.api.artifacts.VersionCatalogsExtension

group = "com.proton.proton_denoise"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.2.21"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.12.0")
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

    androidResources {
        noCompress += listOf("tar.gz", "tgz", "tar")
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    val deepfilterRoot = file("${projectDir}/../third_party/deepfilter")
    val deepfilterModel = File(deepfilterRoot, "models/DeepFilterNet3_onnx.tar.gz")
    val deepfilterJniLibs = File(deepfilterRoot, "lib/android")
    val deepfilterAssetsDir = layout.buildDirectory.dir("deepfilter-assets")

    tasks.register<Copy>("stageDeepFilterAssets") {
        from(deepfilterModel)
        into(deepfilterAssetsDir.map { it.dir("deepfilter") })
        onlyIf { deepfilterModel.isFile }
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
            if (deepfilterJniLibs.isDirectory) {
                jniLibs.srcDir(deepfilterJniLibs)
            }
            assets.srcDir(deepfilterAssetsDir)
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    tasks.named("preBuild").configure {
        dependsOn("stageDeepFilterAssets")
    }

    defaultConfig {
        minSdk = 24
        // Match Meet app ABI slices (android/app/build.gradle). Legacy 32-bit x86 is omitted;
        // dtln-rs prebuilts exist for armeabi-v7a, arm64-v8a, x86_64 only.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
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
    compileOnly("io.github.webrtc-sdk:android:144.7559.09")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.23.0")
}
