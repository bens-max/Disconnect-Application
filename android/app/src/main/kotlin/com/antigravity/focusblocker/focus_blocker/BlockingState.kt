package com.antigravity.focusblocker.focus_blocker

import android.content.SharedPreferences
import android.os.SystemClock
import java.util.Calendar

/**
 * Single place for the native blocking keys and the small amount of time math
 * shared by the service, the accessibility service, the receivers and the
 * MethodChannel handler.
 */
object BlockingState {
    const val PREFS_NAME = "com.antigravity.focusblocker.focus_blocker"

    const val PREF_BLOCKED_APPS = "blocked_apps_native"
    const val PREF_BLOCK_END_TIME = "block_end_time"
    const val PREF_BLOCK_END_ELAPSED = "block_end_elapsed"
    const val PREF_IS_BLOCKING_ACTIVE = "is_blocking_active"
    const val PREF_WHOLE_DEVICE_MODE = "whole_device_mode"
    const val PREF_DEVICE_LOCK_REQUESTED = "device_lock_requested"
    const val PREF_DAILY_SCHEDULE_ENABLED = "daily_schedule_enabled"
    const val PREF_DAILY_SCHEDULE_START = "daily_schedule_start"
    const val PREF_DAILY_SCHEDULE_END = "daily_schedule_end"

    fun currentMinutes(nowMillis: Long = System.currentTimeMillis()): Int {
        val calendar = Calendar.getInstance().apply { timeInMillis = nowMillis }
        return calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
    }

    fun isWithinDailyWindow(
        currentMinutes: Int,
        startMinutes: Int,
        endMinutes: Int,
    ): Boolean =
        if (startMinutes < endMinutes) {
            currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            currentMinutes >= startMinutes || currentMinutes < endMinutes
        }

    /**
     * Wall-clock timestamp of the next schedule boundary: the window end while
     * the window is open, otherwise the next window start.
     */
    fun nextDailyBoundary(
        nowMillis: Long,
        startMinutes: Int,
        endMinutes: Int,
    ): Long {
        val inWindow = isWithinDailyWindow(currentMinutes(nowMillis), startMinutes, endMinutes)
        val targetMinutes = if (inWindow) endMinutes else startMinutes
        val target = Calendar.getInstance().apply {
            timeInMillis = nowMillis
            set(Calendar.HOUR_OF_DAY, targetMinutes / 60)
            set(Calendar.MINUTE, targetMinutes % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (target.timeInMillis <= nowMillis) {
            target.add(Calendar.DAY_OF_YEAR, 1)
        }
        return target.timeInMillis
    }

    /**
     * Remaining time for a one-shot session. The elapsed-realtime value is the
     * authority while the device has not rebooted; the wall-clock value is the
     * fallback for older state written by previous app versions.
     */
    fun remainingSessionMillis(
        prefs: SharedPreferences,
        nowWall: Long = System.currentTimeMillis(),
        nowElapsed: Long = SystemClock.elapsedRealtime(),
    ): Long {
        val elapsedEnd = prefs.getLong(PREF_BLOCK_END_ELAPSED, 0L)
        if (elapsedEnd > 0L) {
            return (elapsedEnd - nowElapsed).coerceAtLeast(0L)
        }
        val wallEnd = prefs.getLong(PREF_BLOCK_END_TIME, 0L)
        return (wallEnd - nowWall).coerceAtLeast(0L)
    }

    fun hasActiveOneShotSession(prefs: SharedPreferences): Boolean =
        prefs.getBoolean(PREF_IS_BLOCKING_ACTIVE, false) &&
            remainingSessionMillis(prefs) > 0L

    fun isSessionActive(prefs: SharedPreferences): Boolean {
        if (prefs.getBoolean(PREF_DAILY_SCHEDULE_ENABLED, false)) {
            return isWithinDailyWindow(
                currentMinutes(),
                prefs.getInt(PREF_DAILY_SCHEDULE_START, 0),
                prefs.getInt(PREF_DAILY_SCHEDULE_END, 0),
            )
        }
        return hasActiveOneShotSession(prefs)
    }
}
