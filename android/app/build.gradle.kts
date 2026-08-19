import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.northernappdev.healthyfast"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    defaultConfig {
        // App identity on Google Play (must match the Play Console listing).
        applicationId = "co.healthyfast"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 36 
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One codebase, two Play bundles in the same listing:
    //   phone → no watch feature (delivered to phones/tablets)
    //   watch → declares android.hardware.type.watch (delivered to Wear OS)
    // Same applicationId, distinct versionCodes (watch = phone + 1).
    flavorDimensions += "formfactor"
    productFlavors {
        create("phone") {
            dimension = "formfactor"
            versionCode = flutter.versionCode * 10
        }
        create("watch") {
            dimension = "formfactor"
            versionCode = flutter.versionCode * 10 + 1
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Uses the release keystore when android/key.properties exists,
            // otherwise falls back to debug signing so `flutter run --release` works.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Eksplisitt R8-oppsett. Flutter-pluginen slår i praksis på begge
            // for release-bygg i dag (verifisert: alle dex i v221-bundlen har
            // markøren "r8-mode":"full", og mapping.txt/resources.txt skrives),
            // men vi setter dem her så byggene ikke avhenger av at pluginens
            // defaults holder seg uendret ved neste Flutter-oppgradering.
            // Google krever begge to for at appen skal regnes som optimalisert:
            // developer.android.com/topic/performance/app-optimization/enable-app-optimization
            isMinifyEnabled = true
            isShrinkResources = true
            // Keep-regler for flutter_local_notifications (GSON) — uten disse
            // vises ikke planlagte varsler i release-bygg. Se proguard-rules.pro.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // Wear OS: ask the paired watch to open the Play Store listing
    implementation("androidx.wear:wear-remote-interactions:1.1.0")
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    // ProtoLayout proto artifacts (also fixes CVE-2024-7254; 1.3.0 > fixed).
    implementation("androidx.wear.protolayout:protolayout-proto:1.3.0")
    implementation("androidx.wear.protolayout:protolayout-external-protobuf:1.3.0")
    // Wear OS watch face complications (elapsed / remaining fast time)
    implementation("androidx.wear.watchface:watchface-complications-data-source:1.2.1")
    // Wear OS Ongoing Activity (active fast on watch face / Recents / Tile)
    implementation("androidx.wear:wear-ongoing:1.0.0")
    // OngoingActivity uses the NotificationCompat helpers from core.
    implementation("androidx.core:core:1.13.1")
    // MÅ være >= 1.10.0. Play Console flagget "avviklede API-er for
    // heldekkende skjerm": enableEdgeToEdge() i 1.9.0 kaller ubetinget
    // Window.setStatusBarColor / setNavigationBarColor /
    // setNavigationBarDividerColor / setDecorFitsSystemWindows, som alle er
    // deprecated fra API 35. Fra 1.10.0 velger biblioteket EdgeToEdgeApi35,
    // som lar systemet styre bar-fargene og dermed dropper kallene.
    // (Flutter-motorens egen PlatformPlugin kaller fortsatt de samme API-ene —
    // det er en åpen oppstrømsbug, flutter/flutter#175262, og kan bare fikses
    // ved å oppgradere Flutter SDK.)
    implementation("androidx.activity:activity-ktx:1.11.0")
    // Wear OS Tiles + ProtoLayout (active-fast tile).
    // tiles 1.5.0 + protolayout 1.3.0 is the matched pair; required because
    // tiles 1.4.1 can throw SecurityException on Wear 5 (API 34) when the app
    // targets API 35+ (flagged by Play Console).
    implementation("androidx.wear.tiles:tiles:1.5.0")
    implementation("androidx.wear.protolayout:protolayout:1.3.0")
    implementation("androidx.wear.protolayout:protolayout-material:1.3.0")
    // ResolvableFuture for the tile service (avoids pulling in full Guava).
    implementation("androidx.concurrent:concurrent-futures:1.1.0")
    // On-device Gemini Nano for meal calorie estimation (ML Kit GenAI Prompt API)
    // beta2 kreves for Gemini nano-v3 (Pixel 10-serien); beta1 ga UNAVAILABLE
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // Health Connect for deduplicated steps (aggregate API).
    // MÅ matche versjonen health-pluginen (12.0.0) er kompilert mot —
    // ellers krasjer writeWorkoutData med NoSuchMethodError på
    // ExerciseSessionRecord-konstruktøren (native, kan ikke fanges i Dart).
    // Sjekk: health-<ver>/android/build.gradle før du endrer denne.
    implementation("androidx.health.connect:connect-client:1.1.0-alpha07")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.1")
}
