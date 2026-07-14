plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("REVV_ANDROID_KEYSTORE_PATH")
val releaseKeystorePassword = System.getenv("REVV_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("REVV_ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("REVV_ANDROID_KEY_PASSWORD")

android {
    namespace = "com.revv.revv_app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.revv.revv_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseKeystorePath?.let(::file)
            storePassword = releaseKeystorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val releaseTaskRequested = allTasks.any {
        it.name.contains("Release", ignoreCase = true)
    }
    val releaseCredentials = listOf(
        releaseKeystorePath,
        releaseKeystorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    )
    if (releaseTaskRequested && releaseCredentials.any { it.isNullOrBlank() }) {
        throw GradleException(
            "Android release signing requires the REVV_ANDROID_KEYSTORE_* environment variables.",
        )
    }
}

flutter {
    source = "../.."
}
