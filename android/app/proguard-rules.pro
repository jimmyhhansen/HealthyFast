# Android system classes used via reflection (BitmapFactory.Options, etc.)
-keepclassmembers class android.graphics.BitmapFactory$Options {
    <fields>;
}

# flutter_local_notifications: planlagte varsler serialiseres med GSON og
# gjenoppbygges i ScheduledNotificationReceiver. Uten disse keep-reglene
# stripper/obfuskerer R8 klassene i release-bygg, og receiveren feiler stille —
# alarmen fyrer, men ingen varsel vises. (Umiddelbare show()-varsler rammes ikke.)
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.google.gson.**

# R8 full mode: GSON TypeToken mister generisk typeinformasjon uten disse.
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
-keepclassmembers class * extends com.google.gson.reflect.TypeToken {
    <fields>;
}

# ML Kit GenAI Prompt API (beta): Generation.getClient() kaster
# NullPointerException i minifiserte release-bygg (observert 2026-07-02 på
# Pixel 10 Pro; debug virker). Beta-biblioteket mangler komplette
# consumer-regler. ML Kit oppdager interne komponenter via reflection
# (ComponentRegistrar i mlkit_common), så hele ML Kit-stakken må fredes —
# ikke bare genai-pakkene.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_genai_prompt.** { *; }
-dontwarn com.google.mlkit.**

# ---------------------------------------------------------------------------
# Defensive regler lagt til 2026-08-02. Bibliotekene under bruker refleksjon
# og/eller Kotlin-metadata på samme måte som ML Kit og GSON gjorde da de
# knakk i full mode. De hadde ingen egne regler her fra før, og feilmodusen
# er stille: klassen finnes ikke lenger i release, og funksjonen feiler kun
# på ekte enhet. Reglene koster noen få kB.
# ---------------------------------------------------------------------------

# Health Connect: connect-client instansierer record-typer via refleksjon
# fra Kotlin-metadata (androidx.health.connect.client.records.*). Uten dette
# kan skriving/lesing feile med NoSuchMethodError i minifiserte bygg — samme
# klasse feil som ExerciseSessionRecord-krasjen notert i build.gradle.kts.
-keep class androidx.health.connect.client.records.** { *; }
-keep class androidx.health.connect.client.units.** { *; }
-keep class androidx.health.platform.client.** { *; }
-dontwarn androidx.health.**

# Firebase Firestore serialiserer/deserialiserer via refleksjon på felt.
# Cloud backup skriver per-record-dokumenter, så feltnavn må overleve.
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName <fields>;
    @com.google.firebase.firestore.PropertyName <methods>;
}
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.firebase.**

# Google Sign-In / Credential Manager (google_sign_in v7).
-keep class com.google.android.libraries.identity.googleid.** { *; }
-dontwarn com.google.android.libraries.identity.googleid.**

# Wear OS tiles + ProtoLayout bygger layout via protobuf-refleksjon.
-keep class androidx.wear.protolayout.** { *; }
-keep class androidx.wear.tiles.** { *; }
-dontwarn androidx.wear.**

# Protobuf-generert kode (protolayout-external-protobuf) — standardregel,
# ellers strippes felt-accessorene som genereres på byggetid.
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}
-dontwarn com.google.protobuf.**

# Kotlin coroutines: ServiceLoader-oppslag av hovedtråd-dispatcheren.
-keep class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }
-dontwarn kotlinx.coroutines.**
