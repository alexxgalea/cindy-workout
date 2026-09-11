plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val videoRegressionEnabled = providers.gradleProperty("cindyVideoRegression").orNull == "true"
val recordVideoGoldens = providers.gradleProperty("cindyVideoGolden").orNull == "true"

android {
    namespace = "com.cindy.tracker"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.cindy.tracker"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        testInstrumentationRunnerArguments["videoRegression"] = videoRegressionEnabled.toString()
        testInstrumentationRunnerArguments["recordGoldens"] = recordVideoGoldens.toString()

        // Phones are ARM. The x86 TFLite libraries are ~9 MB of emulator-only payload.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // The .tflite asset must not be compressed or the Interpreter cannot mmap it.
    androidResources {
        noCompress += "tflite"
        // Video fixtures are copied to the device from the test APK before decoding.
        noCompress += "mp4"
        noCompress += "mov"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        viewBinding = true
    }

    sourceSets {
        // Keep licenced/large fixtures at the repository root, outside the application APK and
        // outside git. The instrumentation APK sees them as assets/fixtures and assets/scenarios.
        getByName("androidTest").assets.srcDir("../tests")
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.activity:activity-ktx:1.9.2")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.6")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    // The launch window. Backports the API 31 SplashScreen to minSdk 26, so the arcs cover
    // process start on every device rather than a white flash on most of them.
    implementation("androidx.core:core-splashscreen:1.0.1")

    val cameraX = "1.4.1"
    implementation("androidx.camera:camera-core:$cameraX")
    implementation("androidx.camera:camera-camera2:$cameraX")
    implementation("androidx.camera:camera-lifecycle:$cameraX")
    implementation("androidx.camera:camera-view:$cameraX")
    implementation("androidx.camera:camera-video:$cameraX")
    // OverlayEffect: draws into the recorded stream, not just the preview.
    implementation("androidx.camera:camera-effects:$cameraX")

    implementation("org.tensorflow:tensorflow-lite:2.16.1")

    testImplementation("junit:junit:4.13.2")

    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

tasks.register("videoRegressionTest") {
    group = "verification"
    description = "Runs offline MoveNet video regression scenarios on a connected emulator/device."
    dependsOn("connectedDebugAndroidTest")
}
