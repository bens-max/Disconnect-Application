package com.antigravity.focusblocker.focus_blocker

import android.app.*
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.util.*

/**
 * Foreground Service that manages the app blocking logic.
 * This service runs in the background and ensures blocking continuity.
 */
class AppBlockingService : Service() {
    
    private lateinit var sharedPreferences: SharedPreferences
    private var blockedApps = setOf<String>()
    private var blockEndTime = 0L
    private var blockingTimer: Timer? = null
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "focus_blocker_channel"

    companion object {
        const val ACTION_START_BLOCKING = "com.antigravity.focusblocker.START_BLOCKING"
        const val ACTION_STOP_BLOCKING = "com.antigravity.focusblocker.STOP_BLOCKING"
        const val ACTION_UPDATE_BLOCKING = "com.antigravity.focusblocker.UPDATE_BLOCKING"
    }

    override fun onCreate() {
        super.onCreate()
        sharedPreferences = getSharedPreferences("com.antigravity.focusblocker.focus_blocker", MODE_PRIVATE)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_BLOCKING -> {
                val blockedAppsList = intent.getStringArrayListExtra("blocked_apps") ?: emptyList()
                val endTime = intent.getLongExtra("end_time", 0L)
                startBlockingSession(blockedAppsList, endTime)
            }
            ACTION_STOP_BLOCKING -> {
                stopBlockingSession()
            }
            ACTION_UPDATE_BLOCKING -> {
                updateBlockingInfo()
            }
        }
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Starts a new blocking session
     */
    private fun startBlockingSession(blockedAppsList: List<String>, endTime: Long) {
        blockedApps = blockedAppsList.toSet()
        blockEndTime = endTime

        // Save to SharedPreferences for accessibility service
        sharedPreferences.edit().apply {
            putStringSet("blocked_apps_native", blockedApps)
            putLong("block_end_time", blockEndTime)
            putBoolean("is_blocking_active", true)
            apply()
        }

        // Start foreground notification
        startForeground(NOTIFICATION_ID, buildNotification())

        // Start the blocking timer to check expiration
        startBlockingTimer()
    }

    /**
     * Stops the blocking session
     */
    private fun stopBlockingSession() {
        blockingTimer?.cancel()
        blockingTimer = null

        sharedPreferences.edit().apply {
            putBoolean("is_blocking_active", false)
            putStringSet("blocked_apps_native", emptySet())
            apply()
        }

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * Starts a timer to check blocking expiration
     */
    private fun startBlockingTimer() {
        blockingTimer?.cancel()
        blockingTimer = Timer()
        
        blockingTimer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                val now = System.currentTimeMillis()
                
                // If blocking time expired, stop the service
                if (now >= blockEndTime) {
                    stopBlockingSession()
                } else {
                    // Update notification with time left
                    val timeLeft = blockEndTime - now
                    updateNotification(timeLeft)
                }
            }
        }, 0, 1000) // Check every second
    }

    /**
     * Updates notification with current blocking info
     */
    private fun updateNotification(timeLeftMillis: Long) {
        val notification = buildNotification(timeLeftMillis)
        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    /**
     * Builds the notification for the foreground service
     */
    private fun buildNotification(timeLeftMillis: Long = 0): Notification {
        val hours = timeLeftMillis / 3600000
        val minutes = (timeLeftMillis % 3600000) / 60000
        val seconds = (timeLeftMillis % 60000) / 1000
        
        val timeText = String.format(
            Locale.getDefault(),
            "%02d:%02d:%02d",
            hours, minutes, seconds
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Focus Blocker Active")
            .setContentText("Apps blocked for $timeText")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)

        // Create an intent to open the app
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        builder.setContentIntent(pendingIntent)

        return builder.build()
    }

    /**
     * Creates notification channel for Android 8.0+
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Focus Blocker",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for Focus Blocker blocking sessions"
                enableLights(true)
                enableVibration(true)
            }
            
            val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    /**
     * Updates blocking information (called when data changes)
     */
    private fun updateBlockingInfo() {
        blockedApps = sharedPreferences.getStringSet("blocked_apps_native", emptySet()) ?: emptySet()
        blockEndTime = sharedPreferences.getLong("block_end_time", 0L)
    }

    override fun onDestroy() {
        blockingTimer?.cancel()
        super.onDestroy()
    }
}
