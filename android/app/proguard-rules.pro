# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# SuperLyricApi
-keep class com.hchen.superlyricapi.** { *; }
-dontwarn com.hchen.superlyricapi.**

# Media3
-keep class androidx.media3.** { *; }

# Flutter deferred components (not bundled in direct APK)
-dontwarn com.google.android.play.core.**

# WebView JS Plugin Bridge
-keepclassmembers class com.sodapulse.music.SodaJsPluginRuntime$NativeBridge {
    @android.webkit.JavascriptInterface <methods>;
}

# ZXing QR core
-dontwarn com.google.zxing.**
