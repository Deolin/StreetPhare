# ============================================================================
# 1. Android Platform & Framework Basics
# ============================================================================

# Keep all standard Android components and views
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider
-keep public class * extends android.app.backup.BackupAgentHelper
-keep public class * extends android.preference.Preference

# Keep custom views and their constructors (crucial for XML layout inflation)
-keep public class * extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
    public void set*(...);
}

# Keep native methods (JNI)
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep UI click handlers referenced directly in XML layout files
-keepclassmembers class * extends android.app.Activity {
    public void *(android.view.View);
}

# ============================================================================
# 2. Debugging & Stack Traces
# ============================================================================

# Preserve original line numbers and source file attributes for readable crash reports
-keepattributes SourceFile,LineNumberTable

# Preserve annotations and generic types (essential for reflection/serialization)
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# ============================================================================
# 3. Data Models / Serialization (JSON, Database, etc.)
# ============================================================================

# Crucial: Protect your Data Transfer Objects (DTOs) and models from obfuscation.
# If fields are renamed, JSON parsers (Gson, Jackson, Moshi) or local databases 
# won't be able to map the data correctly.
# Replace 'com.yourpackage.data.models' with your actual package path.

-keep class com.yourpackage.data.models.** { *; }

# ============================================================================
# 4. Common Library Configurations (If applicable)
# ============================================================================

# For Jetpack Compose (R8 usually handles this automatically, but good to have)
-keepclassmembers class * {
    @androidx.compose.runtime.Composable *;
}

# Suppress warnings from platform dependencies that don't affect your runtime
-dontwarn android.ext.**
-dontwarn javax.annotation.**

# ============================================================================
# 5. GraphHopper 7.0 — classes absentes du runtime Android (R8)
# ============================================================================
# Ces classes sont référencées par GraphHopper mais ne sont PAS fournies
# sur Android, car la fonctionnalité associée est inutilisée :
#
#   * javax.xml.stream.*  → StAX, utilisé uniquement pour lire des .osm XML
#                           (on lit des .pbf via protobuf-java, conservé)
#   * javax.lang.model.*  → API du compilateur Java, absente du runtime Android
#
# Sans ces -dontwarn, R8 échoue avec « Missing classes detected ».
# (protobuf-java et jts-core ayant été ré-inclus dans build.gradle.kts,
#  leurs classes ne sont plus « manquantes » → pas besoin de -dontwarn.)

# --- API compilateur Java (GraphHopper IntEncodedValueImpl) ---
-dontwarn javax.lang.model.SourceVersion

# --- StAX (parseur XML stream, absent d'Android — lecture .pbf uniquement) ---
-dontwarn javax.xml.stream.XMLInputFactory
-dontwarn javax.xml.stream.XMLStreamException
-dontwarn javax.xml.stream.XMLStreamReader
