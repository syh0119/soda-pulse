pluginManagement {
    val flutterSdkPath = run {
        val localProps = file("local.properties")
        if (localProps.exists()) {
            val properties = java.util.Properties()
            localProps.inputStream().use { properties.load(it) }
            val sdk = properties.getProperty("flutter.sdk")
            if (!sdk.isNullOrBlank()) return@run sdk
        }
        val envSdk = System.getenv("FLUTTER_ROOT")
        require(!envSdk.isNullOrBlank()) { "flutter.sdk not set in local.properties and FLUTTER_ROOT not set" }
        envSdk
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
