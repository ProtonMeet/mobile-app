group = "me.proton.meet.video_effects"
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

android {
    namespace = "me.proton.meet.video_effects"

    compileSdk = 36

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
    }

    androidResources {
        noCompress += listOf("tflite")
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

// LiteRT V1 keeps the org.tensorflow.lite Java API but ships 16 KB-aligned native libs.
private val litertVersion = "1.4.2"

configurations.configureEach {
    exclude(group = "org.tensorflow", module = "tensorflow-lite")
    exclude(group = "org.tensorflow", module = "tensorflow-lite-api")
    exclude(group = "org.tensorflow", module = "tensorflow-lite-gpu")
    exclude(group = "org.tensorflow", module = "tensorflow-lite-gpu-api")
}

dependencies {
    implementation("androidx.exifinterface:exifinterface:1.4.1")
    implementation("com.google.mediapipe:tasks-vision:0.10.35")
    implementation("com.google.ai.edge.litert:litert:$litertVersion")
    implementation("com.google.ai.edge.litert:litert-api:$litertVersion")
    implementation("com.google.ai.edge.litert:litert-gpu:$litertVersion")
    implementation("com.google.ai.edge.litert:litert-gpu-api:$litertVersion")
    // flutter_webrtc ships WebRTC at runtime; compileOnly avoids duplicate classes.
    compileOnly("io.github.webrtc-sdk:android:144.7559.01")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
