package com.streetphare.downloader

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.*
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.*
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Mini-installer StreetPhare — Activity unique.
 *
 * <p>Fonctionnement :
 * <ol>
 *   <li>Vérifie la connectivité réseau.</li>
 *   <li>Télécharge le dernier APK complet StreetPhare depuis GitHub Releases
 *       dans le cache externe de l'appareil.</li>
 *   <li>Lance l'installation via {@link android.content.Intent#ACTION_VIEW}
 *       avec un Uri de fichier (Android 8+) ou via {@link StubInstaller}
 *       (API 21-24).</li>
 * </ol>
 *
 * <p>Pas de Material/AndroidX — uniquement des widgets système pour
 * minimiser la taille de l'APK (~50 ko).
 */
class DownloadActivity : Activity() {

    companion object {
        private const val TAG = "StPhareInstaller"

        // URL GitHub Releases — on prend la dernière release tagguée.
        // Format : https://github.com/$owner/$repo/releases/download/$tag/$filename
        private const val GITHUB_RELEASE_URL =
            "https://github.com/Deolin/StreetPhare/releases/latest/download/streetphare.apk"

        // Fallback vers une URL en dur si le redirect latest/download échoue.
        private const val GITHUB_FALLBACK_URL =
            "https://github.com/Deolin/StreetPhare/releases/download/v2.2.0/streetphare.apk"

        // Nom du fichier APK téléchargé.
        private const val APK_FILENAME = "streetphare.apk"

        // Timeout téléchargement (30 secondes).
        private const val DOWNLOAD_TIMEOUT_MS = 30_000
    }

    private lateinit var statusText: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var actionButton: Button
    private var downloadThread: Thread? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Construit l'UI minimale par code — pas de XML layout pour éviter
        // les références AAPT/AAPT2 et réduire la taille APK de ~5 ko.
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(40, 80, 40, 40)
        }

        // Icône texte (pas de drawable lourd)
        val icon = TextView(this).apply {
            text = "📡"
            textSize = 48f
            gravity = Gravity.CENTER
        }
        root.addView(icon)

        // Titre
        val title = TextView(this).apply {
            text = "StreetPhare Installer"
            textSize = 18f
            gravity = Gravity.CENTER
            setPadding(0, 20, 0, 10)
        }
        root.addView(title)

        // Statut
        statusText = TextView(this).apply {
            text = "Préparation…"
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, 10, 0, 16)
        }
        root.addView(statusText)

        // Barre de progression
        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            isIndeterminate = false
            progress = 0
        }
        root.addView(progressBar)

        // Bouton
        actionButton = Button(this).apply {
            text = "Télécharger StreetPhare"
            isEnabled = false
            setOnClickListener { startDownload() }
        }
        root.addView(actionButton)

        setContentView(root)

        Log.i(TAG, "Mini-installer démarré — v1.0.0")

        // Vérifie la connectivité puis active le bouton.
        checkConnectivity()
    }

    override fun onDestroy() {
        // Interrompt le téléchargement si l'utilisateur quitte.
        downloadThread?.interrupt()
        super.onDestroy()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Vérification réseau
    // ═══════════════════════════════════════════════════════════════════════

    private fun checkConnectivity() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: run {
            statusText.text = "❌ Aucune connexion réseau.\nActivez le Wi-Fi ou les données mobiles."
            actionButton.text = "Réessayer"
            actionButton.isEnabled = true
            actionButton.setOnClickListener { checkConnectivity() }
            return
        }
        val caps = cm.getNetworkCapabilities(network)
        if (caps == null || !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            statusText.text = "❌ Réseau sans accès Internet.\nVérifiez votre connexion."
            actionButton.text = "Réessayer"
            actionButton.isEnabled = true
            return
        }
        // Connectivité OK.
        statusText.text = "✅ Connexion Internet détectée.\nPrêt à télécharger StreetPhare."
        actionButton.text = "Télécharger StreetPhare"
        actionButton.isEnabled = true
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Téléchargement
    // ═══════════════════════════════════════════════════════════════════════

    private fun startDownload() {
        actionButton.isEnabled = false
        progressBar.progress = 0
        statusText.text = "⏳ Téléchargement en cours…"

        downloadThread = thread(name = "stphare-dl") {
            try {
                val apkFile = downloadApk()
                runOnUiThread { onDownloadComplete(apkFile) }
            } catch (e: InterruptedException) {
                Log.i(TAG, "Téléchargement interrompu.")
                runOnUiThread {
                    statusText.text = "⏹ Téléchargement annulé."
                    actionButton.isEnabled = true
                }
            } catch (e: Exception) {
                Log.e(TAG, "Erreur téléchargement : ${e.message}", e)
                runOnUiThread {
                    statusText.text = "❌ Erreur : ${e.message}\nVérifiez votre connexion."
                    actionButton.text = "Réessayer"
                    actionButton.isEnabled = true
                }
            }
        }
    }

    @Throws(Exception::class)
    private fun downloadApk(): File {
        val cacheDir = externalCacheDir ?: cacheDir
        val outputFile = File(cacheDir, APK_FILENAME)

        // Tente d'abord le redirect latest/download.
        val url = try {
            downloadFromUrl(GITHUB_RELEASE_URL, outputFile)
            GITHUB_RELEASE_URL
        } catch (e: Exception) {
            Log.w(TAG, "Échec URL principale, tentative fallback…")
            downloadFromUrl(GITHUB_FALLBACK_URL, outputFile)
            GITHUB_FALLBACK_URL
        }

        Log.i(TAG, "✅ APK téléchargé depuis $url — ${outputFile.length()} octets")
        return outputFile
    }

    @Throws(Exception::class)
    private fun downloadFromUrl(urlString: String, outputFile: File) {
        val url = URL(urlString)
        val connection = url.openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = DOWNLOAD_TIMEOUT_MS
            connection.readTimeout = DOWNLOAD_TIMEOUT_MS
            connection.instanceFollowRedirects = true
            connection.requestMethod = "GET"

            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                throw Exception("HTTP $responseCode — ${connection.responseMessage}")
            }

            val contentLength = connection.contentLength
            val totalSize = if (contentLength > 0) contentLength.toLong() else -1L

            connection.inputStream.use { input ->
                FileOutputStream(outputFile).use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    var totalRead = 0L
                    var lastProgressUpdate = 0L

                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        // Vérifie l'interruption du thread.
                        if (Thread.currentThread().isInterrupted) {
                            throw InterruptedException("Téléchargement interrompu")
                        }
                        output.write(buffer, 0, bytesRead)
                        totalRead += bytesRead

                        // Met à jour la progression (max 4 fois par seconde).
                        val now = System.currentTimeMillis()
                        if (totalSize > 0 && now - lastProgressUpdate > 250) {
                            val progress = ((totalRead * 100) / totalSize).toInt()
                            val readableSize = formatBytes(totalRead)
                            val readableTotal = formatBytes(totalSize)
                            runOnUiThread {
                                progressBar.progress = progress
                                statusText.text = "⏳ $readableSize / $readableTotal"
                            }
                            lastProgressUpdate = now
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Installation
    // ═══════════════════════════════════════════════════════════════════════

    private fun onDownloadComplete(apkFile: File) {
        statusText.text = "✅ Téléchargement terminé !\n${formatBytes(apkFile.length())}"
        progressBar.progress = 100
        actionButton.text = "Installer StreetPhare"
        actionButton.isEnabled = true
        actionButton.setOnClickListener { installApk(apkFile) }
    }

    private fun installApk(apkFile: File) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Android 8+ : l'utilisateur doit autoriser "sources inconnues"
                // pour cette app avant l'installation.
                if (!packageManager.canRequestPackageInstalls()) {
                    AlertDialog.Builder(this)
                        .setTitle("Autorisation requise")
                        .setMessage("Pour installer StreetPhare, vous devez autoriser " +
                                "cette application à installer des APK.\n\n" +
                                "Paramètres → Installer des apps inconnues → " +
                                "StreetPhare Installer → Autoriser")
                        .setPositiveButton("Ouvrir les paramètres") { _, _ ->
                            val intent = Intent(
                                android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES
                            ).apply {
                                data = android.net.Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                        .setNegativeButton("Annuler", null)
                        .show()
                    return
                }
            }

            // Lance l'installation via ACTION_VIEW.
            val apkUri = androidx.core.content.FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apkFile
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            startActivity(intent)

            statusText.text = "📦 Installation lancée.\nVérifiez les notifications Android."

            Log.i(TAG, "Installation déclenchée pour ${apkFile.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Erreur installation : ${e.message}", e)
            statusText.text = "❌ Erreur installation : ${e.message}"
            actionButton.isEnabled = true
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Utilitaires
    // ═══════════════════════════════════════════════════════════════════════

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes o"
            bytes < 1024 * 1024 -> "${bytes / 1024} Ko"
            else -> "${"%.1f".format(bytes.toDouble() / (1024 * 1024))} Mo"
        }
    }
}