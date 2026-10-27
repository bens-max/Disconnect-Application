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
    private var isBlockingActive = false
    private var wholeDeviceMode = false
    private var deviceLockRequested = false

    // Packages that are always allowed even in whole-device mode
    // (system UI, launcher, lock screen)
    private val systemAllowedPackages = setOf(
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

    // Our own package is only reliable after the context is attached, so it is
    // added lazily instead of being hard-coded in the list above.
    private val alwaysAllowedPackages: Set<String> by lazy {
        systemAllowedPackages + packageName
    }

    /**
     * Keeps the cached blocking state in sync with SharedPreferences.
     *
     * Listener callbacks are delivered on the main thread, which is also where
     * [onAccessibilityEvent] runs, so all fields above are main-thread confined
     * and need no locking. This also keeps all preference I/O off the
     * accessibility event path, which can fire many times per second.
     */
    private val preferenceListener =
        SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            when (key) {
                PREF_BLOCKED_APPS,
                PREF_IS_BLOCKING_ACTIVE,
                PREF_WHOLE_DEVICE_MODE,
                PREF_DEVICE_LOCK_REQUESTED -> updateBlockingData()
            }
        }

    override fun onServiceConnected() {
        super.onServiceConnected()

        sharedPreferences = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        sharedPreferences.registerOnSharedPreferenceChangeListener(preferenceListener)

        // Only window transitions are needed to detect foreground app changes.
        // TYPE_WINDOW_CONTENT_CHANGED is intentionally excluded: it fires very
        // frequently (scrolling, typing, animations) and adds no value here.
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
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
        if (deviceLockRequested) {
            clearDeviceLockRequest()
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Honour relock requests from ScreenOnReceiver (set via AppBlockingService)
        if (deviceLockRequested) {
            clearDeviceLockRequest()
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            return
        }

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOWS_CHANGED -> Unit
            else -> return
        }

        // `is_blocking_active` is maintained authoritatively by AppBlockingService,
        // so no additional time check is needed here (it would race its timer).
        if (!isBlockingActive) return

        val eventPackage = event.packageName?.toString() ?: return

        if (wholeDeviceMode) {
            // Whole-device mode: block every app that isn't ours or a system shell
            if (!alwaysAllowedPackages.contains(eventPackage)) {
                // Re-lock the screen to enforce the whole-device disconnect
                performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            }
        } else {
            // Selected-apps mode: only block the apps the user picked
            if (eventPackage != packageName && blockedApps.contains(eventPackage)) {
                redirectToHomeScreen()
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
        blockedApps = sharedPreferences.getStringSet(PREF_BLOCKED_APPS, emptySet()) ?: emptySet()
        wholeDeviceMode = sharedPreferences.getBoolean(PREF_WHOLE_DEVICE_MODE, false)
        isBlockingActive = sharedPreferences.getBoolean(PREF_IS_BLOCKING_ACTIVE, false)
        deviceLockRequested = sharedPreferences.getBoolean(PREF_DEVICE_LOCK_REQUESTED, false)
    }

    private fun clearDeviceLockRequest() {
        deviceLockRequested = false
        sharedPreferences.edit().putBoolean(PREF_DEVICE_LOCK_REQUESTED, false).apply()
    }

    override fun onDestroy() {
        if (::sharedPreferences.isInitialized) {
            sharedPreferences.unregisterOnSharedPreferenceChangeListener(preferenceListener)
        }
        super.onDestroy()
    }

    private companion object {
        const val PREFS_NAME = "com.antigravity.focusblocker.focus_blocker"
        const val PREF_BLOCKED_APPS = "blocked_apps_native"
        const val PREF_IS_BLOCKING_ACTIVE = "is_blocking_active"
        const val PREF_WHOLE_DEVICE_MODE = "whole_device_mode"
        const val PREF_DEVICE_LOCK_REQUESTED = "device_lock_requested"
    }
}
