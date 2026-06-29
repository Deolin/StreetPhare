# ProGuard rules for StreetPhare mini-downloader.
#
# Objectif : APK < 100 ko — on conserve UNIQUEMENT le code utilisé.
# Aucune règle spéciale nécessaire car le mini-downloader n'utilise
# pas de bibliothèques externes ni de réflexion.

# Conserver l'Activity principale (point d'entrée).
-keep class com.streetphare.downloader.DownloadActivity { *; }

# Conserver les classes Android standard utilisées.
-keep class android.net.** { *; }
-keep class java.net.** { *; }
-keep class java.io.** { *; }