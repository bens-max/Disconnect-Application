package com.antigravity.focusblocker.focus_blocker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Date

/**
 * Foreground service that owns the session state and the persistent
 * notification.
 *
 * It does not tick. The notification uses a system-rendered chronometer and a
 * single Handler callback is scheduled for the next state change (session end
 * or schedule boundary). This keeps wakeups near zero while a session is idle.
 */
class AppBlockingService : Service() {

    private lateinit var sharedPreferences: SharedPreferences
    private var screenOnReceiver: ScreenOnReceiver? = null

    private val handler = Handler(Looper.getMainLooper())
    private val boundaryRunnable = Runnable { onBoundaryReached() }

    private val notificationId = 1001
    private val channelId = "disconnect_focus_session_v2"
    private val legacyChannelId = "focus_blocker_channel"

    companion object {
        private const val TAG = "AppBlockingService"
        const val ACTION_START_BLOCKING = "com.antigravity.focusblocker.START_BLOCKING"
        const val ACTION_STOP_BLOCKING = "com.antigravity.focusblocker.STOP_BLOCKING"
        const val ACTION_START_DAILY_SCHEDULE = "com.antigravity.focusblocker.START_DAILY_SCHEDULE"
        private const val STALE_ELAPSED_TOLERANCE_MS = 5 * 60 * 1000L
    }

    override fun onCreate() {
        super.onCreate()
        sharedPreferences = getSharedPreferences(BlockingState.PREFS_NAME, MODE_PRIVATE)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_BLOCKING -> {
                val blockedApps = intent.getStringArrayListExtra("blocked_apps") ?: emptyList()
                val endTime = intent.getLongExtra("end_time", 0L)
                startBlockingSession(blockedApps, endTime)
            }
            ACTION_START_DAILY_SCHEDULE -> {
                val blockedApps = intent.getStringArrayListExtra("blocked_apps") ?: emptyList()
                val startMinutes = intent.getIntExtra("start_minutes", 0)
                val endMinutes = intent.getIntExtra("end_minutes", 0)
                startDailySchedule(blockedApps, startMinutes, endMinutes)
            }
            ACTION_STOP_BLOCKING -> {
                stopBlockingSession()
                return START_NOT_STICKY
            }
            else -> restoreBlockingSession()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startBlockingSession(blockedApps: List<String>, endTimeWall: Long) {
        cancelScheduledWork()
        val nowWall = System.currentTimeMillis()
        val remainingWall = endTimeWall - nowWall
        if (remainingWall <= 0L) {
            stopBlockingSession()
            return
        }

        val endElapsed = SystemClock.elapsedRealtime() + remainingWall
        val wholeDevice = sharedPreferences.getBoolean(BlockingState.PREF_WHOLE_DEVICE_MODE, false)

        sharedPreferences.edit().apply {
            putStringSet(BlockingState.PREF_BLOCKED_APPS, blockedApps.toSet())
            putLong(BlockingState.PREF_BLOCK_END_TIME, endTimeWall)
            putLong(BlockingState.PREF_BLOCK_END_ELAPSED, endElapsed)
            putBoolean(BlockingState.PREF_IS_BLOCKING_ACTIVE, true)
            putBoolean(BlockingState.PREF_DAILY_SCHEDULE_ENABLED, false)
            remove(BlockingState.PREF_DAILY_SCHEDULE_START)
            remove(BlockingState.PREF_DAILY_SCHEDULE_END)
            putBoolean(BlockingState.PREF_DEVICE_LOCK_REQUESTED, false)
            apply()
        }

        promoteToForeground()
        if (wholeDevice) registerScreenOnReceiver() else unregisterScreenOnReceiver()
        scheduleCallback(remainingWall)
    }

    private fun startDailySchedule(
        blockedApps: List<String>,
        startMinutes: Int,
        endMinutes: Int,
    ) {
        cancelScheduledWork()
        sharedPreferences.edit().apply {
            putStringSet(BlockingState.PREF_BLOCKED_APPS, blockedApps.toSet())
            putInt(BlockingState.PREF_DAILY_SCHEDULE_START, startMinutes)
            putInt(BlockingState.PREF_DAILY_SCHEDULE_END, endMinutes)
            putBoolean(BlockingState.PREF_DAILY_SCHEDULE_ENABLED, true)
            putBoolean(BlockingState.PREF_IS_BLOCKING_ACTIVE, true)
            putBoolean(BlockingState.PREF_WHOLE_DEVICE_MODE, false)
            putBoolean(BlockingState.PREF_DEVICE_LOCK_REQUESTED, false)
            remove(BlockingState.PREF_BLOCK_END_TIME)
            remove(BlockingState.PREF_BLOCK_END_ELAPSED)
            apply()
        }
        promoteToForeground()
        unregisterScreenOnReceiver()
        scheduleNextDailyBoundary()
    }

    /**
     * Called by the system after START_STICKY restart (null intent) or after a
     * reboot/package update.
     */
    private fun restoreBlockingSession() {
        val dailyEnabled = sharedPreferences.getBoolean(
            BlockingState.PREF_DAILY_SCHEDULE_ENABLED,
            false,
        )
        if (dailyEnabled) {
            promoteToForeground()
            scheduleNextDailyBoundary()
            return
        }

        val wallEnd = sharedPreferences.getLong(BlockingState.PREF_BLOCK_END_TIME, 0L)
        val wallRemaining = (wallEnd - System.currentTimeMillis()).coerceAtLeast(0L)
        val remaining = BlockingState.remainingSessionMillis(sharedPreferences)

        // A stale elapsed timestamp from before a reboot can be much larger than
        // the wall-clock remaining time. Trust the wall clock in that case.
        if (remaining > wallRemaining + STALE_ELAPSED_TOLERANCE_MS) {
            sharedPreferences.edit()
                .putLong(
                    BlockingState.PREF_BLOCK_END_ELAPSED,
                    SystemClock.elapsedRealtime() + wallRemaining,
                )
                .apply()
        }

        if (!sharedPreferences.getBoolean(BlockingState.PREF_IS_BLOCKING_ACTIVE, false) ||
            BlockingState.remainingSessionMillis(sharedPreferences) <= 0L
        ) {
            stopBlockingSession()
            return
        }

        promoteToForeground()
        val wholeDevice = sharedPreferences.getBoolean(
            BlockingState.PREF_WHOLE_DEVICE_MODE,
            false,
        )
        if (wholeDevice) registerScreenOnReceiver() else unregisterScreenOnReceiver()
        scheduleCallback(BlockingState.remainingSessionMillis(sharedPreferences))
    }

    private fun stopBlockingSession() {
        cancelScheduledWork()
        unregisterScreenOnReceiver()

        sharedPreferences.edit().apply {
            putBoolean(BlockingState.PREF_IS_BLOCKING_ACTIVE, false)
            putStringSet(BlockingState.PREF_BLOCKED_APPS, emptySet())
            remove(BlockingState.PREF_BLOCK_END_TIME)
            remove(BlockingState.PREF_BLOCK_END_ELAPSED)
            putBoolean(BlockingState.PREF_DAILY_SCHEDULE_ENABLED, false)
            remove(BlockingState.PREF_DAILY_SCHEDULE_START)
            remove(BlockingState.PREF_DAILY_SCHEDULE_END)
            putBoolean(BlockingState.PREF_WHOLE_DEVICE_MODE, false)
            putBoolean(BlockingState.PREF_DEVICE_LOCK_REQUESTED, false)
            apply()
        }

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun onBoundaryReached() {
        if (sharedPreferences.getBoolean(BlockingState.PREF_DAILY_SCHEDULE_ENABLED, false)) {
            // The window changed: the notification text and its countdown target
            // change at each boundary, so update it once and arm the next one.
            updateNotification()
            scheduleNextDailyBoundary()
            return
        }

        if (BlockingState.remainingSessionMillis(sharedPreferences) <= 0L) {
            stopBlockingSession()
        } else {
            // Defensive: the callback fired slightly early (or the process was
            // paused); re-arm for the actual remaining time.
            scheduleCallback(BlockingState.remainingSessionMillis(sharedPreferences))
        }
    }

    private fun scheduleCallback(delayMillis: Long) {
        handler.removeCallbacks(boundaryRunnable)
        handler.postDelayed(boundaryRunnable, delayMillis.coerceAtLeast(1L))
    }

    private fun scheduleNextDailyBoundary() {
        val now = System.currentTimeMillis()
        val start = sharedPreferences.getInt(BlockingState.PREF_DAILY_SCHEDULE_START, 0)
        val end = sharedPreferences.getInt(BlockingState.PREF_DAILY_SCHEDULE_END, 0)
        val boundary = BlockingState.nextDailyBoundary(now, start, end)
        scheduleCallback((boundary - now).coerceAtLeast(1_000L))
    }

    private fun cancelScheduledWork() {
        handler.removeCallbacks(boundaryRunnable)
    }

    private fun promoteToForeground() {
        try {
            startForeground(notificationId, buildNotification())
        } catch (e: Exception) {
            // The manifest declares the specialUse foreground service type and
            // its permission, so this should not happen. Fail safely rather than
            // crashing the whole process.
            Log.e(TAG, "startForeground failed", e)
            stopSelf()
        }
    }

    private fun updateNotification() {
        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(notificationId, buildNotification())
    }

    private fun buildNotification(): Notification {
        val nowWall = System.currentTimeMillis()
        val dailyEnabled = sharedPreferences.getBoolean(
            BlockingState.PREF_DAILY_SCHEDULE_ENABLED,
            false,
        )

        val title: String
        val text: String
        val countdownTarget: Long

        if (dailyEnabled) {
            val start = sharedPreferences.getInt(BlockingState.PREF_DAILY_SCHEDULE_START, 0)
            val end = sharedPreferences.getInt(BlockingState.PREF_DAILY_SCHEDULE_END, 0)
            val active = BlockingState.isWithinDailyWindow(
                BlockingState.currentMinutes(nowWall),
                start,
                end,
            )
            countdownTarget = BlockingState.nextDailyBoundary(nowWall, start, end)
            title = if (active) "Disconnect is blocking apps" else "Disconnect schedule"
            text =
                if (active) {
                    "Blocked until ${formatTime(countdownTarget)}"
                } else {
                    "Next block starts at ${formatTime(countdownTarget)}"
                }
        } else {
            countdownTarget = nowWall + BlockingState.remainingSessionMillis(sharedPreferences)
            title = "Disconnect is active"
            text = "Selected apps are blocked"
        }

        val contentIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(true)
            .setWhen(countdownTarget)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .build()
    }

    private fun formatTime(millis: Long): String {
        val formatter = android.text.format.DateFormat.getTimeFormat(this)
        return formatter.format(Date(millis))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        // Remove the old high-importance channel. Its vibration/lights and
        // importance cannot be changed after creation.
        notificationManager.deleteNotificationChannel(legacyChannelId)

        val channel = NotificationChannel(
            channelId,
            "Focus session",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows the active Disconnect focus session"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
            setSound(null, null)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun registerScreenOnReceiver() {
        if (screenOnReceiver != null) return
        screenOnReceiver = ScreenOnReceiver()
        ContextCompat.registerReceiver(
            this,
            screenOnReceiver,
            IntentFilter(Intent.ACTION_SCREEN_ON),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    private fun unregisterScreenOnReceiver() {
        screenOnReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already unregistered; ignore.
            }
            screenOnReceiver = null
        }
    }

    override fun onDestroy() {
        cancelScheduledWork()
        unregisterScreenOnReceiver()
        super.onDestroy()
    }
}
