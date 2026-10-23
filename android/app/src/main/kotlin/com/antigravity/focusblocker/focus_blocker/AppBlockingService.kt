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
    private var dailyScheduleStart = 0
    private var dailyScheduleEnd = 0
    private var dailySchedule = false
    private var blockingTimer: Timer? = null
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "focus_blocker_channel"

    companion object {
        const val ACTION_START_BLOCKING = "com.antigravity.focusblocker.START_BLOCKING"
        const val ACTION_STOP_BLOCKING = "com.antigravity.focusblocker.STOP_BLOCKING"
        const val ACTION_UPDATE_BLOCKING = "com.antigravity.focusblocker.UPDATE_BLOCKING"
        const val ACTION_START_DAILY_SCHEDULE = "com.antigravity.focusblocker.START_DAILY_SCHEDULE"
    }

    override fun onCreate() {
        super.onCreate()
        sharedPreferences = getSharedPreferences("com.antigravity.focusblocker.focus_blocker", MODE_PRIVATE)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            restoreBlockingSession()
            return START_STICKY
        }

        when (intent?.action) {
            ACTION_START_BLOCKING -> {
                val blockedAppsList = intent.getStringArrayListExtra("blocked_apps") ?: emptyList()
                val endTime = intent.getLongExtra("end_time", 0L)
                startBlockingSession(blockedAppsList, endTime)
            }
            ACTION_START_DAILY_SCHEDULE -> {
                val blockedAppsList = intent.getStringArrayListExtra("blocked_apps") ?: emptyList()
                val startMinutes = intent.getIntExtra("start_minutes", 0)
                val endMinutes = intent.getIntExtra("end_minutes", 0)
                startDailySchedule(blockedAppsList, startMinutes, endMinutes)
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

    private fun restoreBlockingSession() {
        updateBlockingInfo()
        if (!sharedPreferences.getBoolean("is_blocking_active", false)) {
            stopSelf()
            return
        }

        if (!dailySchedule && blockEndTime <= System.currentTimeMillis()) {
            stopBlockingSession()
            return
        }

        startForeground(NOTIFICATION_ID, buildNotification())
        startBlockingTimer()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Starts a new blocking session
     */
    private fun startBlockingSession(blockedAppsList: List<String>, endTime: Long) {
        dailySchedule = false
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

    private fun startDailySchedule(
        blockedAppsList: List<String>,
        startMinutes: Int,
        endMinutes: Int,
    ) {
        blockedApps = blockedAppsList.toSet()
        dailyScheduleStart = startMinutes
        dailyScheduleEnd = endMinutes
        dailySchedule = true
        sharedPreferences.edit().apply {
            putStringSet("blocked_apps_native", blockedApps)
            putInt("daily_schedule_start", startMinutes)
            putInt("daily_schedule_end", endMinutes)
            putBoolean("daily_schedule_enabled", true)
            putBoolean("is_blocking_active", true)
            apply()
        }
        startForeground(NOTIFICATION_ID, buildNotification())
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
            remove("block_end_time")
            putBoolean("daily_schedule_enabled", false)
            putBoolean("whole_device_mode", false)
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
                
                if (!dailySchedule && now >= blockEndTime) {
                    stopBlockingSession()
                } else if (dailySchedule) {
                    val inWindow = isDailyScheduleActive(now)
                    sharedPreferences.edit()
                        .putBoolean("is_blocking_active", inWindow)
                        .apply()
                    updateNotification(dailyScheduleTimeLeft(now))
                } else {
                    updateNotification(blockEndTime - now)
                }

            }
        }, 0, 1000) // Check every second
    }

    private fun dailyScheduleTimeLeft(now: Long): Long {
        val calendar = Calendar.getInstance().apply { timeInMillis = now }
        val currentMinutes = calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
        val inWindow = if (dailyScheduleStart < dailyScheduleEnd) {
            currentMinutes >= dailyScheduleStart && currentMinutes < dailyScheduleEnd
        } else {
            currentMinutes >= dailyScheduleStart || currentMinutes < dailyScheduleEnd
        }

        val target = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, if (inWindow) dailyScheduleEnd / 60 else dailyScheduleStart / 60)
            set(Calendar.MINUTE, if (inWindow) dailyScheduleEnd % 60 else dailyScheduleStart % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if ((inWindow && dailyScheduleEnd <= dailyScheduleStart) ||
                (!inWindow && currentMinutes >= dailyScheduleStart)) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        return (target.timeInMillis - now).coerceAtLeast(0)
    }

    private fun isDailyScheduleActive(now: Long): Boolean {
        val calendar = Calendar.getInstance().apply { timeInMillis = now }
        val currentMinutes = calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
        return if (dailyScheduleStart < dailyScheduleEnd) {
            currentMinutes >= dailyScheduleStart && currentMinutes < dailyScheduleEnd
        } else {
            currentMinutes >= dailyScheduleStart || currentMinutes < dailyScheduleEnd
        }
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
        dailyScheduleStart = sharedPreferences.getInt("daily_schedule_start", 0)
        dailyScheduleEnd = sharedPreferences.getInt("daily_schedule_end", 0)
        dailySchedule = sharedPreferences.getBoolean("daily_schedule_enabled", false)
    }

    override fun onDestroy() {
        blockingTimer?.cancel()
        super.onDestroy()
    }
}
