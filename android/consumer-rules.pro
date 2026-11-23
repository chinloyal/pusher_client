# Rules applied to apps that use pusher_client (shipped via consumerProguardFiles).

# pusher-java-client deserialises protocol messages with gson reflection.
-keep class com.pusher.client.** { *; }
-keepclassmembers class com.pusher.client.** { *; }
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod

# gson
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# This plugin
-keep class com.github.chinloyal.pusher_client.** { *; }

# Optional dependencies referenced by Java-WebSocket / pusher-java-client
-dontwarn org.slf4j.**
-dontwarn javax.annotation.**
