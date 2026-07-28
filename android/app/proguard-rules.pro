# Add project specific ProGuard rules here.
-keepattributes *Annotation*

# Keep alarm + flutter_local_notifications callback.
-keep class com.dexterous.** { *; }
-keep class dev.fluttercommunity.plus.alarm.** { *; }

# Supabase Flutter
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase / FCM
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
