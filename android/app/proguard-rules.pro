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

# Firebase Crashlytics
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.google.firebase.crashlytics.** { *; }
-dontwarn com.google.firebase.crashlytics.**

# Jellyfin / Media3 / ExoPlayer (native player stack)
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Flutter deferred components reference Play Core; we ship a single AAB (no split APKs).
-dontwarn com.google.android.play.core.**

# OxTelegramStreamBridge: openSessionAsync/ensureAvailableAsync/cancelCurrentRead are invoked
# from native code (go/oxtelegram/cshared_android/jni_bridge.go, CallStaticVoidMethod) —  R8 has
# no visibility into that call site and will strip/rename these as unreachable, which makes
# GetStaticMethodID return null and the native side abort() on the next call. Must keep whole.
-keep class app.oxplayer.tdlibbridge.player.OxTelegramStreamBridge { *; }
