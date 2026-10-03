import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val videoRegressionEnabled = providers.gradleProperty("cindyVideoRegression").orNull == "true"
val recordVideoGoldens = providers.gradleProperty("cindyVideoGolden").orNull == "true"

// Upload signing. Absent on a machine that has never released — the release build then falls
// back to unsigned, which fails loudly at upload time rather than quietly producing a build
// nobody can install. Never committed.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// Strava API credentials, read the same way as keystoreProperties above. Absent on CI and a
// fresh clone — the build then bakes in empty strings, and StravaConfig.available goes false,
// which hides the whole feature rather than failing the build.
val stravaProperties = Properties().apply {
    val f = rootProject.file("strava.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// A raw property value can carry a quote or a backslash; without escaping, that would either
// break out of the generated string literal or fail to compile.
fun String.asBuildConfigLiteral() = "\"" + replace("\\", "\\\\").replace("\"", "\\\"") + "\""

android {
    namespace = "com.cindy.tracker"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.cindy.tracker"
        minSdk = 26
        // Google Play has required API 36 for new apps and updates since 2026-08-31. The next
        // bump is due around August 2027, and it is the one that ends the portrait opt-out in
        // AndroidManifest.xml.
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        testInstrumentationRunnerArguments["videoRegression"] = videoRegressionEnabled.toString()
        testInstrumentationRunnerArguments["recordGoldens"] = recordVideoGoldens.toString()

        // Phones are ARM. The x86 TFLite libraries are ~9 MB of emulator-only payload.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }

        // Empty strings when strava.properties is absent — see StravaConfig.available.
        buildConfigField(
            "String", "STRAVA_CLIENT_ID",
            (stravaProperties.getProperty("clientId") ?: "").asBuildConfigLiteral()
        )
        buildConfigField(
            "String", "STRAVA_CLIENT_SECRET",
            (stravaProperties.getProperty("clientSecret") ?: "").asBuildConfigLiteral()
        )
    }

    signingConfigs {
        if (keystoreProperties.getProperty("storeFile") != null) {
            create("upload") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload")
            // Deliberately off. proguard-rules.pro is empty, and TFLite reaches for classes
            // reflectively — R8 would strip them with nothing failing at compile time, and the
            // first sign of it would be a crash on a stranger's phone. Turning this on means
            // writing keep rules AND re-running the on-device benchmarks, not flipping a flag.
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
        // BuildConfig.DEBUG gates the measurement instruments (the model swap and the latency
        // readout) out of release builds. AGP 8 does not generate the class unless asked.
        buildConfig = true
    }

    testOptions {
        unitTests {
            // Robolectric inflates the real layouts and applies the real styles, so the smoke
            // tests need the resource table rather than the stub android.jar.
            isIncludeAndroidResources = true
        }
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
    // ExploreByTouchHelper, so each point of a drawn chart is its own TalkBack stop. Already in
    // the graph through Material; declared so the chart does not lean on a transitive.
    implementation("androidx.customview:customview:1.1.0")

    val cameraX = "1.4.1"
    implementation("androidx.camera:camera-core:$cameraX")
    implementation("androidx.camera:camera-camera2:$cameraX")
    implementation("androidx.camera:camera-lifecycle:$cameraX")
    implementation("androidx.camera:camera-view:$cameraX")
    implementation("androidx.camera:camera-video:$cameraX")
    // OverlayEffect: draws into the recorded stream, not just the preview.
    implementation("androidx.camera:camera-effects:$cameraX")

    // LiteRT is TensorFlow Lite under its new name, with the same org.tensorflow.lite API, so
    // PoseDetector is unchanged. It replaces tensorflow-lite 2.16.1, whose arm64 library is
    // linked for 4 KB pages, which a 16 KB phone may refuse to load. Stay on 1.4.x: 2.x brings a
    // different native runtime and API, which is its own decision with its own benchmarks.
    implementation("com.google.ai.edge.litert:litert:1.4.2")

    // Drives the Strava upload after a workout is saved: survives process death, waits for a
    // network, and backs off between retries on its own.
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    testImplementation("junit:junit:4.13.2")
    // Builds the screens for real on the JVM. The suite was 200 tests of pure logic and none of
    // a single view, which is how a null layoutParams reached a device.
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core:1.6.1")
    // Android ships org.json at runtime, but plain JVM tests need the real artifact, so that
    // Strava payload and response parsing are testable without Robolectric.
    testImplementation("org.json:json:20240303")
    // TestListenableWorkerBuilder and a synchronous WorkManager for the upload worker's tests.
    testImplementation("androidx.work:work-testing:2.9.1")

    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

tasks.register("videoRegressionTest") {
    group = "verification"
    description = "Runs offline MoveNet video regression scenarios on a connected emulator/device."
    dependsOn("connectedDebugAndroidTest")
}
