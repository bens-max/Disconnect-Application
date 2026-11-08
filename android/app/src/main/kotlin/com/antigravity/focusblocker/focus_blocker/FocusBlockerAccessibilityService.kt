package com.antigravity.focusblocker.focus_blocker

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.telecom.TelecomManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager

/**
 * Detects when the user opens a blocked app and sends them back home (or
 * re-locks the screen in whole-device mode).
 *
 * The event path is intentionally tiny. The only work done for an event is an
 * in-memory look at the package name; SharedPreferences is read in the
 * preference-change listener and when the service connects, never per event.
 */
class FocusBlockerAccessibilityService : AccessibilityService() {

    private lateinit var sharedPreferences: SharedPreferences

    // All fields below are only mutated on the main thread (the listener, the
    // service callbacks and onAccessibilityEvent all run there).
    private var blockedApps: Set<String> = emptySet()
    private var isBlockingActive = false
    private var wholeDeviceMode = false
    private var deviceLockRequested = false
    private var dailyScheduleEnabled = false
    private var dailyScheduleStart = 0
    private var dailyScheduleEnd = 0
    private var blockEndElapsed = 0L
    private var blockEndWall = 0L

    private var lastPackage: String? = null
    private var lastPackageAt = 0L

    // Debug-only counters; only scheduled when the APK is debuggable. They let
    // us measure the real event rate with adb logcat.
    private var isDebuggable = false
    private var debugEventCount = 0L
    private val debugHandler = Handler(Looper.getMainLooper())
    private val debugLogRunnable = object : Runnable {
        override fun run() {
            logDebugEventCount(debugEventCount)
            debugEventCount = 0
            debugHandler.postDelayed(this, DEBUG_LOG_INTERVAL_MS)
        }
    }

    // Packages that must never be blocked: a wrong package name here would
    // otherwise trap the user outside of their phone (or outside the app while
    // an emergency call is being placed).
    private val systemAllowedPackages = setOf(
        "android",
        "com.android.systemui",
        "com.android.settings",
        "com.android.launcher",
        "com.android.launcher2",
        "com.android.launcher3",
        "com.google.android.apps.nexuslauncher",
        "com.sec.android.app.launcher",
        "com.huawei.android.launcher",
        "com.miui.home",
        "com.coloros.launcher",
        "com.oppo.launcher",
        "com.vivo.launcher",
        "com.zte.mifavor.launcher",
        "com.android.dialer",
        "com.google.android.dialer",
        "com.android.phone",
        "com.google.android.phone",
        "com.android.emergency",
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller"
    )

    private var imePackages: Set<String> = emptySet()

    // Launchers and the emergency dialer vary by OEM and by user choice. Resolve
    // them at runtime so whole-device mode cannot lock the user out of their own
    // home screen or the phone app.
    private val homePackages: Set<String> by lazy {
        packageManager.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            0,
        ).mapNotNull { it.activityInfo?.packageName }.toSet()
    }

    private val defaultDialerPackage: String? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            (getSystemService(TELECOM_SERVICE) as? TelecomManager)?.defaultDialerPackage
        } else {
            null
        }
    }

    // Our own package is only reliable after the context is attached, so it is
    // added lazily instead of being hard-coded in the list above.
    private val alwaysAllowedPackages: Set<String> by lazy {
        systemAllowedPackages +
            packageName +
            imePackages +
            homePackages +
            listOfNotNull(defaultDialerPackage)
    }

    private val preferenceListener =
        SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            when (key) {
                BlockingState.PREF_BLOCKED_APPS,
                BlockingState.PREF_IS_BLOCKING_ACTIVE,
                BlockingState.PREF_WHOLE_DEVICE_MODE,
                BlockingState.PREF_DEVICE_LOCK_REQUESTED,
                BlockingState.PREF_DAILY_SCHEDULE_ENABLED,
                BlockingState.PREF_DAILY_SCHEDULE_START,
                BlockingState.PREF_DAILY_SCHEDULE_END,
                BlockingState.PREF_BLOCK_END_TIME,
                BlockingState.PREF_BLOCK_END_ELAPSED -> updateBlockingData()
            }
        }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this

        sharedPreferences = getSharedPreferences(BlockingState.PREFS_NAME, MODE_PRIVATE)
        isDebuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        sharedPreferences.registerOnSharedPreferenceChangeListener(preferenceListener)
        imePackages = readEnabledInputMethods()

        // typeWindowStateChanged is enough to see a new foreground app.
        // No content retrieval and no key-event filtering: both add work to
        // every window/key event on the whole device.
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = 0
            notificationTimeout = 100
        }
        setServiceInfo(info)

        updateBlockingData()

        if (isDebuggable) {
            debugHandler.postDelayed(debugLogRunnable, DEBUG_LOG_INTERVAL_MS)
        }

        if (deviceLockRequested) {
            clearDeviceLockRequest()
            lockScreen()
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (isDebuggable) debugEventCount++
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        // A relock requested by ScreenOnReceiver / the Flutter lock button.
        if (deviceLockRequested) {
            clearDeviceLockRequest()
            lockScreen()
            return
        }

        val eventPackage = event.packageName?.toString() ?: return
        val now = SystemClock.elapsedRealtime()

        // Ignore repeated window events for the same package (dialog opening,
        // IME window changes, activity re-creation, ...).
        if (eventPackage == lastPackage && now - lastPackageAt < DEBOUNCE_MS) return
        lastPackage = eventPackage
        lastPackageAt = now

        if (eventPackage == packageName || eventPackage in alwaysAllowedPackages) return
        if (!isSessionActiveNow()) return

        if (wholeDeviceMode) {
            lockScreen()
        } else if (blockedApps.contains(eventPackage)) {
            performGlobalAction(GLOBAL_ACTION_HOME)
        }
    }

    override fun onInterrupt() {
        // Called when an interruption occurs; no action needed.
    }

    /** Reads the latest blocking configuration. Called from pref callbacks only. */
    private fun updateBlockingData() {
        blockedApps = sharedPreferences
            .getStringSet(BlockingState.PREF_BLOCKED_APPS, emptySet())
            ?.toSet() ?: emptySet()
        isBlockingActive = sharedPreferences
            .getBoolean(BlockingState.PREF_IS_BLOCKING_ACTIVE, false)
        wholeDeviceMode = sharedPreferences
            .getBoolean(BlockingState.PREF_WHOLE_DEVICE_MODE, false)
        deviceLockRequested = sharedPreferences
            .getBoolean(BlockingState.PREF_DEVICE_LOCK_REQUESTED, false)
        dailyScheduleEnabled = sharedPreferences
            .getBoolean(BlockingState.PREF_DAILY_SCHEDULE_ENABLED, false)
        dailyScheduleStart = sharedPreferences
            .getInt(BlockingState.PREF_DAILY_SCHEDULE_START, 0)
        dailyScheduleEnd = sharedPreferences
            .getInt(BlockingState.PREF_DAILY_SCHEDULE_END, 0)
        blockEndElapsed = sharedPreferences
            .getLong(BlockingState.PREF_BLOCK_END_ELAPSED, 0L)
        blockEndWall = sharedPreferences
            .getLong(BlockingState.PREF_BLOCK_END_TIME, 0L)
    }

    private fun isSessionActiveNow(): Boolean {
        if (dailyScheduleEnabled) {
            return BlockingState.isWithinDailyWindow(
                BlockingState.currentMinutes(),
                dailyScheduleStart,
                dailyScheduleEnd,
            )
        }
        if (!isBlockingActive) return false
        if (blockEndElapsed > 0L) {
            return SystemClock.elapsedRealtime() < blockEndElapsed
        }
        return System.currentTimeMillis() < blockEndWall
    }

    private fun lockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
        } else {
            // GLOBAL_ACTION_LOCK_SCREEN was added in API 28. On older devices
            // go home instead of pretending the device was locked.
            performGlobalAction(GLOBAL_ACTION_HOME)
        }
    }

    private fun readEnabledInputMethods(): Set<String> {
        return try {
            // Settings.Secure.ENABLED_INPUT_METHODS is not readable by apps
            // targeting Android 14+ (targetSdk 34). InputMethodManager exposes
            // the same list through a public API that needs no permission.
            val inputMethodManager = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
            inputMethodManager.enabledInputMethodList
                .mapNotNull { it.packageName }
                .toSet()
        } catch (e: Exception) {
            Log.w(TAG, "Could not read enabled input methods", e)
            emptySet()
        }
    }

    private fun clearDeviceLockRequest() {
        deviceLockRequested = false
        sharedPreferences.edit()
            .putBoolean(BlockingState.PREF_DEVICE_LOCK_REQUESTED, false)
            .apply()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        if (instance === this) instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        if (isDebuggable) debugHandler.removeCallbacks(debugLogRunnable)
        if (::sharedPreferences.isInitialized) {
            sharedPreferences.unregisterOnSharedPreferenceChangeListener(preferenceListener)
        }
        super.onDestroy()
    }

    companion object {
        private const val TAG = "FocusBlockerA11y"
        private const val DEBOUNCE_MS = 500L
        private const val DEBUG_LOG_INTERVAL_MS = 60_000L

        @Volatile
        private var instance: FocusBlockerAccessibilityService? = null

        /**
         * Locks the screen immediately if the accessibility service is
         * connected. Returns false when it is not connected (for example after
         * the process was killed), so callers can fall back to a flag.
         */
        fun lockScreenNow(): Boolean {
            val service = instance ?: return false
            service.lockScreen()
            return true
        }

        /** Debug-only event counter, called once per minute. */
        fun logDebugEventCount(count: Long) {
            Log.d(TAG, "accessibility events in the last minute: $count")
        }
    }
}
