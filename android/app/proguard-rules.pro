# Release shrinker rules for app.oxplayer (R8 / ProGuard).
# Keep Sentry + Flutter JNI glue readable; mapping upload is via sentry_dart_plugin in CI.

-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Sentry Android SDK
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# Jellyfin / Media3 / ExoPlayer (native player stack)
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
