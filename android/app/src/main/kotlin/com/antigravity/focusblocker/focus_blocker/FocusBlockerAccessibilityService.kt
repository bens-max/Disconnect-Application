package com.antigravity.focusblocker.focus_blocker

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.SharedPreferences
import android.view.accessibility.AccessibilityEvent

/**
 * Custom Accessibility Service for detecting and blocking app launches.
 * This service receives accessibility events and returns to the home screen
 * when a blocked app is detected.
 */
class FocusBlockerAccessibilityService : AccessibilityService() {
    
    private lateinit var sharedPreferences: SharedPreferences
    private var blockedApps = setOf<String>()
    private var blockEndTime = 0L
    private var isBlockingActive = false
    private var dailyScheduleStart = 0
    private var dailyScheduleEnd = 0
    override fun onServiceConnected() {
        super.onServiceConnected()
        
        sharedPreferences = getSharedPreferences(
            "com.antigravity.focusblocker.focus_blocker",
            MODE_PRIVATE
        )
        
        // Configure accessibility service
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPES_ALL_MASK
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
            notificationTimeout = 100
        }
        setServiceInfo(info)
        
        // Load initial blocking data
        updateBlockingData()

        if (sharedPreferences.getBoolean("device_lock_requested", false)) {
            sharedPreferences.edit().putBoolean("device_lock_requested", false).apply()
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            return
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        
        // Refresh blocking data in case it changed
        updateBlockingData()
        
        val sessionActive = if (sharedPreferences.getBoolean("daily_schedule_enabled", false)) {
            isDailyScheduleActive()
        } else {
            isBlockingActive && System.currentTimeMillis() < blockEndTime
        }
        if (!sessionActive) {
            return
        }

        // Check for key events related to app launching
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                val packageName = event.packageName?.toString() ?: return
                
                // If a blocked app is in the foreground, return to the home screen.
                if (packageName != this@FocusBlockerAccessibilityService.packageName &&
                    blockedApps.contains(packageName)) {
                    redirectToHomeScreen()
                }
            }
        }
    }

    override fun onInterrupt() {
        // This is called when an interruption occurs
    }

    /**
     * Leaves the blocked app without showing an intermediate blocking screen.
     */
    private fun redirectToHomeScreen() {
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    /**
     * Updates blocking data from SharedPreferences
     */
    private fun updateBlockingData() {
        synchronized(this) {
            blockedApps = sharedPreferences.getStringSet("blocked_apps_native", emptySet()) ?: emptySet()
            blockEndTime = sharedPreferences.getLong("block_end_time", 0L)
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
