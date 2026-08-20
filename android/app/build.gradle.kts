import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties from key.properties file
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "plus.mylife.spacetime"
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
        applicationId = "plus.mylife.spacetime"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // Required for record plugin
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            require(keystorePropertiesFile.exists()) {
                "Missing android/key.properties — required for Play Store release signing."
            }
            val storeFileName = keystoreProperties.getProperty("storeFile")
                ?: error("key.properties is missing storeFile")
            val releaseStoreFile = file(storeFileName)
            require(releaseStoreFile.exists()) {
                "Release keystore not found at ${releaseStoreFile.absolutePath}"
            }
            storeFile = releaseStoreFile
            storePassword = keystoreProperties.getProperty("storePassword")
                ?: error("key.properties is missing storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
                ?: error("key.properties is missing keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
                ?: error("key.properties is missing keyPassword")
        }
    }

    buildTypes {
        release {
            // Play Store upload: signed with spacetime-release-key.jks only.
            signingConfig = signingConfigs.getByName("release")
            isDebuggable = false
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.mapbox.maps:android:11.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}

flutter {
    source = "../.."
}
