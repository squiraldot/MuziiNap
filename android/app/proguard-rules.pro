# Layer 02 — targeted R8 rules for Android entry points and JNI reflection.
# Do not add package-wide application keep rules here.

# Android framework instantiates these components from AndroidManifest.xml.
-keep class com.merrmist.muziinapmusic.MainActivity { *; }
-keep class com.merrmist.muziinapmusic.BgUtilsPotService { *; }
-keep class com.merrmist.muziinapmusic.LyricsHomeWidgetProvider { *; }

# Flutter's legacy multidex Application is selected by Flutter's manifest placeholder.
-keep class io.flutter.app.FlutterMultiDexApplication { *; }

# audio_service declares these classes by manifest name and Android dispatches
# service and media-button callbacks reflectively.
-keep class com.ryanheise.audioservice.AudioService { *; }
-keep class com.ryanheise.audioservice.MediaButtonReceiver { *; }

# JNIGen resolves these application classes and members by literal JVM class,
# field, constructor, and method names. Renaming/removal would break JNI lookups.
-keep class com.merrmist.muziinapmusic.Equalizer { *; }
-keep class com.merrmist.muziinapmusic.SDKInt { *; }
-keep class com.merrmist.muziinapmusic.SDKInt$Companion { *; }

# Preserve runtime metadata used by reflection and Kotlin/JVM interop.
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
