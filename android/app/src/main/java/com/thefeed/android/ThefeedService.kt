package com.thefeed.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.io.File

// gomobile-generated bindings (from mobile/mobile.go, package `mobile`).
// The Go HTTP server runs in-process via a JNI .so loaded from the AAR
// — no subprocess, no exec from nativeLibraryDir, no PIE/page-size/
// SELinux pitfalls.
import mobile.Mobile
import mobile.Server

class ThefeedService : Service() {
    private var server: Server? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Starting local service..."))
        savePort(-1)
        startServerAsync()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (server == null) startServerAsync()
        return START_STICKY
    }

    override fun onDestroy() {
        try {
            server?.stop()
        } catch (_: Throwable) {
        }
        server = null
        savePort(-1)
        super.onDestroy()
        // Kill the whole app process so the activity doesn't linger.
        android.os.Process.killProcess(android.os.Process.myPid())
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startServerAsync() {
        if (server != null) return
        Thread {
            try {
                val dataDir = File(filesDir, "thefeeddata")
                if (!dataDir.exists()) dataDir.mkdirs()

                // Prefer the last successful port so the WebView origin
                // stays stable across launches (preserves localStorage).
                // 0 lets the kernel pick if no usable preference exists.
                val pref = readSavedPort().let {
                    if (it in PORT_RANGE_MIN..PORT_RANGE_MAX) it else 0
                }

                // BuildConfig.IS_UNIVERSAL is true only for the
                // universal APK (built with -PuniversalBuild=true).
                // Universal users stay on universal across updates;
                // per-arch users stay on their matching split.
                val s = if (BuildConfig.IS_UNIVERSAL) {
                    Mobile.newAndroidUniversalServer(dataDir.absolutePath, pref.toLong())
                } else {
                    Mobile.newAndroidServer(dataDir.absolutePath, pref.toLong())
                }
                server = s
                val port = s.port().toInt()
                savePort(port)
                updateForegroundNotification("Running on http://127.0.0.1:$port")
            } catch (e: Throwable) {
                savePort(-1)
                updateForegroundNotification("Failed: ${e.message ?: e.javaClass.simpleName}")
            }
        }.start()
    }

    private fun readSavedPort(): Int {
        return getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getInt(PREF_PORT, -1)
    }

    private fun savePort(port: Int) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putInt(PREF_PORT, port).apply()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "thefeed background service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps thefeed client running"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(message: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, ThefeedService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("thefeed")
            .setContentText(message)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Exit", stopPendingIntent)
            .setSilent(true)
            .build()
    }

    private fun updateForegroundNotification(message: String) {
        try {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification(message))
        } catch (_: Exception) {
            // Notification permission may not be granted; service still runs.
        }
    }

    companion object {
        const val CHANNEL_ID = "thefeed_service"
        const val NOTIFICATION_ID = 1201
        const val PREFS_NAME = "thefeed_runtime"
        const val PREF_PORT = "port"
        const val ACTION_STOP = "com.thefeed.android.STOP"
        // Stable port window so the WebView origin survives restarts.
        const val PORT_RANGE_MIN = 38000
        const val PORT_RANGE_MAX = 38099
    }
}
