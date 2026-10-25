package com.antigravity.focusblocker.focus_blocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * BroadcastReceiver that detects when the screen turns on and re-locks the device
 * if a whole-device blocking session is currently active.
 *
 * This handles the scenario where the user presses the power button to wake the
 * screen during a whole-device disconnect session. The receiver fires on
 * ACTION_SCREEN_ON and immediately relaunches the lock screen via an intent
 * to the AppBlockingService, which will use the accessibility service to re-lock.
 */
class ScreenOnReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != Intent.ACTION_SCREEN_ON || context == null) return

        val prefs = context.getSharedPreferences(
            "com.antigravity.focusblocker.focus_blocker",
            Context.MODE_PRIVATE
        )

        val isBlockingActive = prefs.getBoolean("is_blocking_active", false)
        val wholeDeviceMode = prefs.getBoolean("whole_device_mode", false)
        val blockEndTime = prefs.getLong("block_end_time", 0L)
        val isDailySchedule = prefs.getBoolean("daily_schedule_enabled", false)

        // Only act when whole-device mode is active and the timer hasn't expired
        if (!isBlockingActive || !wholeDeviceMode) return
        if (!isDailySchedule && blockEndTime <= System.currentTimeMillis()) return

        // Tell the AppBlockingService to re-lock
        val serviceIntent = Intent(context, AppBlockingService::class.java).apply {
            action = AppBlockingService.ACTION_RELOCK_SCREEN
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
