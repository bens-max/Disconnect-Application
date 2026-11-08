package com.antigravity.focusblocker.focus_blocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-locks the screen when it is turned on during a whole-device session.
 *
 * ACTION_SCREEN_ON cannot be declared in the manifest, so the foreground
 * service registers this receiver while whole-device mode is active. The
 * receiver never starts a service: starting a foreground service from a
 * background broadcast is restricted, and the accessibility service is the
 * component that actually performs the lock.
 */
class ScreenOnReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != Intent.ACTION_SCREEN_ON || context == null) return

        val prefs = context.getSharedPreferences(BlockingState.PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(BlockingState.PREF_IS_BLOCKING_ACTIVE, false)) return
        if (!prefs.getBoolean(BlockingState.PREF_WHOLE_DEVICE_MODE, false)) return

        val dailyEnabled = prefs.getBoolean(BlockingState.PREF_DAILY_SCHEDULE_ENABLED, false)
        if (!dailyEnabled) {
            val wallEnd = prefs.getLong(BlockingState.PREF_BLOCK_END_TIME, 0L)
            if (wallEnd <= System.currentTimeMillis()) return
        }

        if (!FocusBlockerAccessibilityService.lockScreenNow()) {
            // The accessibility service is not connected right now. The flag is
            // consumed when it connects, so the session still re-locks after a
            // process restart.
            prefs.edit()
                .putBoolean(BlockingState.PREF_DEVICE_LOCK_REQUESTED, true)
                .apply()
        }
    }
}
