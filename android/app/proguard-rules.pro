# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# UniLinks
-keep class com.getkeepsafe.relinker.** { *; }
-keep class com.google.android.gms.** { *; }

# Play Core
-keep class com.google.android.play.core.** { *; }
-keep class * extends com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep R8 rules
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exception

# Prevent R8 from leaving Data object members always null
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Keep setters in Views so that animations can still work.
-keepclassmembers public class * extends android.view.View {
   void set*(***);
   *** get*();
}

# Keep the support library
-keep class androidx.** { *; }
-keep interface androidx.** { *; }

# Keep methods that are accessed via reflection
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
} 