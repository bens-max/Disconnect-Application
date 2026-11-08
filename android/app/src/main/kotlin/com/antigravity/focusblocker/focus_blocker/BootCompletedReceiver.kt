package com.antigravity.focusblocker.focus_blocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock

/**
 * Restarts a still-active blocking session after a reboot or an app update.
 */
class BootCompletedReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        val action = intent?.action
        if (context == null ||
            (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED)
        ) {
            return
        }

        val prefs = context.getSharedPreferences(BlockingState.PREFS_NAME, Context.MODE_PRIVATE)
        val isBlockingActive = prefs.getBoolean(BlockingState.PREF_IS_BLOCKING_ACTIVE, false)
        val blockEndTime = prefs.getLong(BlockingState.PREF_BLOCK_END_TIME, 0L)
        val dailyScheduleEnabled = prefs.getBoolean(
            BlockingState.PREF_DAILY_SCHEDULE_ENABLED,
            false,
        )

        if (isBlockingActive && dailyScheduleEnabled) {
            val blockedApps = prefs.getStringSet(BlockingState.PREF_BLOCKED_APPS, emptySet())
                ?.toList() ?: emptyList()
            if (blockedApps.isEmpty()) {
                clearState(prefs)
                return
            }
            val serviceIntent = Intent(context, AppBlockingService::class.java).apply {
                this.action = AppBlockingService.ACTION_START_DAILY_SCHEDULE
                putStringArrayListExtra("blocked_apps", ArrayList(blockedApps))
                putExtra("start_minutes", prefs.getInt(BlockingState.PREF_DAILY_SCHEDULE_START, 0))
                putExtra("end_minutes", prefs.getInt(BlockingState.PREF_DAILY_SCHEDULE_END, 0))
            }
            startService(context, serviceIntent)
            return
        }

        if (isBlockingActive && blockEndTime > System.currentTimeMillis()) {
            val blockedApps = prefs.getStringSet(BlockingState.PREF_BLOCKED_APPS, emptySet())
                ?.toList() ?: emptyList()
            val wholeDevice = prefs.getBoolean(BlockingState.PREF_WHOLE_DEVICE_MODE, false)
            if (blockedApps.isEmpty() && !wholeDevice) {
                clearState(prefs)
                return
            }

            // ElapsedRealtime restarts at zero after a reboot. Re-anchor the
            // in-process countdown to the wall-clock end time.
            prefs.edit()
                .putLong(
                    BlockingState.PREF_BLOCK_END_ELAPSED,
                    SystemClock.elapsedRealtime() + (blockEndTime - System.currentTimeMillis()),
                )
                .apply()

            val serviceIntent = Intent(context, AppBlockingService::class.java).apply {
                this.action = AppBlockingService.ACTION_START_BLOCKING
                putStringArrayListExtra("blocked_apps", ArrayList(blockedApps))
                putExtra("end_time", blockEndTime)
            }
            startService(context, serviceIntent)
            return
        }

        if (isBlockingActive) {
            // The session expired while the device was off.
            clearState(prefs)
        }
    }

    private fun startService(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun clearState(prefs: android.content.SharedPreferences) {
        prefs.edit().apply {
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
    }
}
