package com.antigravity.focusblocker.focus_blocker

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.SharedPreferences
import android.view.accessibility.AccessibilityEvent

/**
 * Custom Accessibility Service for detecting and blocking app launches.
 * This service receives accessibility events and returns to the home screen
 * when a blocked app is detected.
 *
 * Whole-device mode: when `whole_device_mode` is true, ALL foreground apps
 * (except our own package) are redirected to the home screen, effectively
 * locking the device to the lock screen for the duration of the timer.
 */
class FocusBlockerAccessibilityService : AccessibilityService() {

    private lateinit var sharedPreferences: SharedPreferences
    private var blockedApps = setOf<String>()
    private var blockEndTime = 0L
    private var isBlockingActive = false
    private var wholeDeviceMode = false
    private var dailyScheduleStart = 0
    private var dailyScheduleEnd = 0

    // Packages that are always allowed even in whole-device mode
    // (system UI, launcher, lock screen, our own app)
    private val alwaysAllowedPackages = setOf(
        "com.android.systemui",
        "com.android.launcher",
        "com.android.launcher2",
        "com.android.launcher3",
        "com.google.android.apps.nexuslauncher",
        "com.sec.android.app.launcher",   // Samsung
        "com.huawei.android.launcher",    // Huawei
        "com.miui.home",                   // Xiaomi
        "com.coloros.launcher",            // OnePlus/ColorOS
        "com.oppo.launcher",
        "com.vivo.launcher",
        "com.zte.mifavor.launcher"
    )

    override fun onServiceConnected() {
        super.onServiceConnected()

        sharedPreferences = getSharedPreferences(
            "com.antigravity.focusblocker.focus_blocker",
            MODE_PRIVATE
        )

        // Configure accessibility service to listen to all window events
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                    AccessibilityEvent.TYPE_WINDOWS_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
            notificationTimeout = 50
        }
        setServiceInfo(info)

        // Load initial blocking data
        updateBlockingData()

        // If a lock was requested (from Flutter side), honour it now
        if (sharedPreferences.getBoolean("device_lock_requested", false)) {
            sharedPreferences.edit().putBoolean("device_lock_requested", false).apply()
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Refresh blocking data on every event so changes take effect immediately
        updateBlockingData()

        // Honour relock requests from ScreenOnReceiver (set via AppBlockingService)
        if (sharedPreferences.getBoolean("device_lock_requested", false)) {
            sharedPreferences.edit().putBoolean("device_lock_requested", false).apply()
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            return
        }

        val sessionActive = if (sharedPreferences.getBoolean("daily_schedule_enabled", false)) {
            isDailyScheduleActive()
        } else {
            isBlockingActive && System.currentTimeMillis() < blockEndTime
        }

        if (!sessionActive) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_WINDOWS_CHANGED -> {
                val packageName = event.packageName?.toString() ?: return

                if (wholeDeviceMode) {
                    // Whole-device mode: block every app that isn't ours or a system shell
                    if (packageName != this.packageName &&
                        !alwaysAllowedPackages.contains(packageName)
                    ) {
                        // Re-lock the screen to enforce the whole-device disconnect
                        performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
                    }
                } else {
                    // Selected-apps mode: only block the apps the user picked
                    if (packageName != this.packageName &&
                        blockedApps.contains(packageName)
                    ) {
                        redirectToHomeScreen()
                    }
                }
            }
        }
    }

    override fun onInterrupt() {
        // Called when an interruption occurs; no action needed.
    }

    /** Returns to the home screen (used for selected-app blocking). */
    private fun redirectToHomeScreen() {
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    /** Reads the latest blocking configuration from SharedPreferences. */
    private fun updateBlockingData() {
        synchronized(this) {
            blockedApps = sharedPreferences.getStringSet("blocked_apps_native", emptySet()) ?: emptySet()
            blockEndTime = sharedPreferences.getLong("block_end_time", 0L)
            wholeDeviceMode = sharedPreferences.getBoolean("whole_device_mode", false)
            isBlockingActive = sharedPreferences.getBoolean("is_blocking_active", false) &&
                    (sharedPreferences.getBoolean("daily_schedule_enabled", false) ||
                            blockEndTime > System.currentTimeMillis())
            dailyScheduleStart = sharedPreferences.getInt("daily_schedule_start", 0)
            dailyScheduleEnd = sharedPreferences.getInt("daily_schedule_end", 0)
        }
    }

    private fun isDailyScheduleActive(): Boolean {
        if (!sharedPreferences.getBoolean("daily_schedule_enabled", false)) return false
        val calendar = java.util.Calendar.getInstance()
        val currentMinutes = calendar.get(java.util.Calendar.HOUR_OF_DAY) * 60 +
                calendar.get(java.util.Calendar.MINUTE)
        return if (dailyScheduleStart < dailyScheduleEnd) {
            currentMinutes >= dailyScheduleStart && currentMinutes < dailyScheduleEnd
        } else {
            currentMinutes >= dailyScheduleStart || currentMinutes < dailyScheduleEnd
        }
    }
}
