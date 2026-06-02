package com.antigravity.focusblocker.focus_blocker

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.Intent
import android.content.SharedPreferences
import android.view.accessibility.AccessibilityEvent
import android.view.KeyEvent

/**
 * Custom Accessibility Service for detecting and blocking app launches.
 * This service receives accessibility events and can launch the blocking activity
 * when a blocked app is detected.
 */
class FocusBlockerAccessibilityService : AccessibilityService() {
    
    private lateinit var sharedPreferences: SharedPreferences
    private var blockedApps = setOf<String>()
    private var blockEndTime = 0L
    private var isBlockingActive = false
    private val activityManager by lazy { getSystemService(ACTIVITY_SERVICE) as ActivityManager }
    private val keyguardManager by lazy { getSystemService(KeyguardManager::class.java) }

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
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        
        // Refresh blocking data in case it changed
        updateBlockingData()
        
        if (!isBlockingActive || System.currentTimeMillis() > blockEndTime) {
            isBlockingActive = false
            return
        }

        // Check for key events related to app launching
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                val packageName = event.packageName?.toString() ?: return
                
                // If a blocked app is in the foreground, launch blocking activity
                if (blockedApps.contains(packageName)) {
                    launchBlockingActivity()
                }
            }
        }
    }

    override fun onKeyEvent(event: KeyEvent?): Boolean {
        // Intercept home button to prevent users from escaping the blocking activity
        if (event != null && event.keyCode == KeyEvent.KEYCODE_HOME) {
            // Let the blocking service handle this
            val foregroundPackage = getForegroundApp()
            if (foregroundPackage != null && blockedApps.contains(foregroundPackage)) {
                launchBlockingActivity()
                return true // Block the home button press
            }
        }
        return super.onKeyEvent(event)
    }

    override fun onInterrupt() {
        // This is called when an interruption occurs
    }

    /**
     * Launches the blocking activity to prevent further app usage
     */
    private fun launchBlockingActivity() {
        try {
            val intent = Intent(this, BlockingActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                putExtra("package_name", getForegroundApp())
                putExtra("end_time", blockEndTime)
            }
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Gets the currently focused/foreground app package name
     */
    private fun getForegroundApp(): String? {
        return try {
            @Suppress("DEPRECATION")
            val tasks = activityManager.getRunningTasks(1)
            if (tasks.isNotEmpty()) {
                tasks[0].topActivity?.packageName
            } else {
                null
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    /**
     * Updates blocking data from SharedPreferences
     */
    private fun updateBlockingData() {
        synchronized(this) {
            blockedApps = sharedPreferences.getStringSet("blocked_apps_native", emptySet()) ?: emptySet()
            blockEndTime = sharedPreferences.getLong("block_end_time", 0L)
            isBlockingActive = sharedPreferences.getBoolean("is_blocking_active", false) &&
                    blockEndTime > System.currentTimeMillis()
        }
    }
}
