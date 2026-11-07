# R8 runs on the release build (app/build.gradle.kts). LiteRT ships its own keep rules for what its
# native code calls back into, in its AAR; the app has no reflection of its own, and every
# Activity, receiver and layout class is kept by the rules AGP derives from the manifest and XML.
# Add a rule here only with the reason, and only after a release build shows the need on a phone.

# Without these a crash in Play Console's vitals shows "SourceFile" and no line numbers. The
# bundle carries the mapping file, and Play uses it to turn the trace back into Kotlin.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
