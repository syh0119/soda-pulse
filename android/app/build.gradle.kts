import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

val releaseStoreFilePath = System.getenv("SODAPULSE_KEYSTORE_PATH")
    ?.takeIf { it.isNotBlank() }
    ?: keystoreProperties.getProperty("storeFile")
val releaseStorePassword = System.getenv("SODAPULSE_KEYSTORE_PASSWORD")
    ?.takeIf { it.isNotBlank() }
    ?: keystoreProperties.getProperty("storePassword")
val releaseKeyAlias = System.getenv("SODAPULSE_KEY_ALIAS")
    ?.takeIf { it.isNotBlank() }
    ?: keystoreProperties.getProperty("keyAlias")
val releaseKeyPassword = System.getenv("SODAPULSE_KEY_PASSWORD")
    ?.takeIf { it.isNotBlank() }
    ?: keystoreProperties.getProperty("keyPassword")
val hasReleaseSigning = !releaseStoreFilePath.isNullOrBlank() &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "com.sodapulse.music"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        applicationId = "com.sodapulse.music"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) {
                throw GradleException(
                    "Release signing config missing: provide android/key.properties or SODAPULSE_KEYSTORE_* env vars."
                )
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-common:1.5.1")
    implementation("com.github.HChenX:SuperLyricApi:4.0")
    implementation("com.google.zxing:core:3.5.3")
    testImplementation("junit:junit:4.13.2")
}
