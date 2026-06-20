// NotificationChannelSetup.kt — StreetPhare v1.5
//
// Configuration native des canaux de notification Android.
//
// Crée 5 canaux correspondant aux catégories définies dans le manifeste :
//   - streetphare_alerts    : Alertes terrain (barrages, nasses, tensions)
//   - streetphare_events    : Événements & Trajets
//   - streetphare_panic     : Alertes Panic collectives
//   - streetphare_messages  : Messages Hive P2P
//   - streetphare_persistent: Notification persistante "StreetPhare actif"
//
// Chaque canal est configuré avec IMPORTANCE_HIGH (niveau 4) pour
// garantir l'affichage en pop-up (heads-up) et le son même en mode
// Ne pas déranger (catégorie ALARM pour les alertes critiques).

package com.example.flutter_streetphare

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build

object NotificationChannelSetup {

    // ── Constantes d'identification ────────────────────────────────────────────

    const val CHANNEL_ALERTS = "streetphare_alerts"
    const val CHANNEL_EVENTS = "streetphare_events"
    const val CHANNEL_PANIC = "streetphare_panic"
    const val CHANNEL_MESSAGES = "streetphare_messages"
    const val CHANNEL_PERSISTENT = "streetphare_persistent"

    // ── Création des canaux ────────────────────────────────────────────────────

    /**
     * Crée tous les canaux de notification StreetPhare.
     * Idempotent : si les canaux existent déjà, ils ne sont pas recréés.
     * Doit être appelé au démarrage (avant toute notification).
     */
    fun createAllChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // ── Canal Alertes terrain (CRITIQUE) ───────────────────────────────────
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ALERTS,
                "Alertes terrain",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Barrages, nasses, zones de tension"
                enableLights(true)
                lightColor = 0xFFE53935.toInt() // Rouge
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 200, 300)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
        )

        // ── Canal Événements & Trajets ─────────────────────────────────────────
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_EVENTS,
                "Événements & Trajets",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Début de trajet, waypoints, fin de manif"
                enableLights(true)
                lightColor = 0xFF2196F3.toInt() // Bleu
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 200, 100, 200)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
        )

        // ── Canal Panic collectif (CRITIQUE) ───────────────────────────────────
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_PANIC,
                "Alertes Panic collectives",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Déclenchement panic multi-appareils"
                enableLights(true)
                lightColor = 0xFFFF0000.toInt() // Rouge vif
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                setBypassDnd(true) // Passe outre Ne pas déranger
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
        )

        // ── Canal Messages Hive P2P ────────────────────────────────────────────
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_MESSAGES,
                "Messages Hive P2P",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Nouveaux messages sur le réseau local"
                enableLights(true)
                lightColor = 0xFF4CAF50.toInt() // Vert
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 100, 100, 100)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
        )

        // ── Canal Notification persistante ─────────────────────────────────────
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_PERSISTENT,
                "StreetPhare actif",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Indique que StreetPhare est actif en arrière-plan"
                enableLights(false)
                enableVibration(false)
                setSound(null, null) // Pas de son pour la notification persistante
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
        )
    }

    /**
     * Supprime tous les canaux StreetPhare (utilitaire de debug).
     */
    fun deleteAllChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.deleteNotificationChannel(CHANNEL_ALERTS)
        manager.deleteNotificationChannel(CHANNEL_EVENTS)
        manager.deleteNotificationChannel(CHANNEL_PANIC)
        manager.deleteNotificationChannel(CHANNEL_MESSAGES)
        manager.deleteNotificationChannel(CHANNEL_PERSISTENT)
    }
}