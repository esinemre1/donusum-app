plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.emrekirik.donusum"
    compileSdk = 34
    compileSdk = 34
    // ndkVersion = "25.1.8937393" // Let AGP decide

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.emrekirik.donusum"
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.5.0"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // signingConfig = signingConfigs.getByName("debug")
            minifyEnabled = false
            shrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
