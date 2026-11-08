package com.antigravity.focusblocker.focus_blocker

import android.Manifest
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val nativeChannel = "com.antigravity.focusblocker/native"
    private lateinit var sharedPreferences: SharedPreferences

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermissionIfNeeded()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sharedPreferences = getSharedPreferences(BlockingState.PREFS_NAME, MODE_PRIVATE)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> result.success(true)
                    "isAccessibilityServiceEnabled" -> result.success(isAccessibilityServiceEnabled())
                    "openAccessibilitySettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                        )
                        result.success(true)
                    }
                    "startBlocking" -> {
                        val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                        val endTimeMillis = call.argument<Long>("endTimeMillis") ?: 0L
                        val wholeDevice = call.argument<Boolean>("wholeDevice") ?: false
                        try {
                            require(endTimeMillis > System.currentTimeMillis()) {
                                "The blocking end time must be in the future"
                            }
                            require(wholeDevice || blockedApps.isNotEmpty()) {
                                "Select at least one app or choose whole-device mode"
                            }
                            startBlocking(blockedApps, endTimeMillis, wholeDevice)
                            result.success(true)
                        } catch (e: IllegalArgumentException) {
                            result.error("INVALID_BLOCKING_REQUEST", e.message, null)
                        } catch (e: SecurityException) {
                            clearFailedBlockingState()
                            result.error(
                                "SERVICE_PERMISSION",
                                "Foreground service permission was denied",
                                e.message,
                            )
                        } catch (e: IllegalStateException) {
                            clearFailedBlockingState()
                            result.error(
                                "SERVICE_START_FAILED",
                                "Foreground service could not be started",
                                e.message,
                            )
                        }
                    }
                    "requestDeviceLock" -> {
                        val locked = FocusBlockerAccessibilityService.lockScreenNow()
                        if (!locked) {
                            sharedPreferences.edit()
                                .putBoolean(BlockingState.PREF_DEVICE_LOCK_REQUESTED, true)
                                .apply()
                        }
                        result.success(locked)
                    }
                    "startDailySchedule" -> {
                        val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                        val startMinutes = call.argument<Int>("startMinutes") ?: 0
                        val endMinutes = call.argument<Int>("endMinutes") ?: 0
                        try {
                            require(blockedApps.isNotEmpty()) {
                                "Select at least one app for a daily schedule"
                            }
                            require(
                                startMinutes in 0..1439 &&
                                    endMinutes in 0..1439 &&
                                    startMinutes != endMinutes,
                            ) {
                                "Daily schedule times must be different valid times"
                            }
                            startDailySchedule(blockedApps, startMinutes, endMinutes)
                            result.success(true)
                        } catch (e: IllegalArgumentException) {
                            result.error("INVALID_SCHEDULE_REQUEST", e.message, null)
                        } catch (e: SecurityException) {
                            clearFailedBlockingState()
                            result.error(
                                "SERVICE_PERMISSION",
                                "Foreground service permission was denied",
                                e.message,
                            )
                        } catch (e: IllegalStateException) {
                            clearFailedBlockingState()
                            result.error(
                                "SERVICE_START_FAILED",
                                "Foreground service could not be started",
                                e.message,
                            )
                        }
                    }
                    "stopBlocking" -> {
                        stopBlocking()
                        result.success(true)
                    }
                    "isBlockingActive" -> result.success(isBlockingActive())
                    "getBlockingStatus" -> result.success(getBlockingStatus())
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        // Reading Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES directly is
        // restricted on newer Android versions. AccessibilityManager exposes
        // the same information through a supported API.
        val manager = getSystemService(ACCESSIBILITY_SERVICE) as? AccessibilityManager
            ?: return false
        return manager.getEnabledAccessibilityServiceList(
            AccessibilityServiceInfo.FEEDBACK_ALL_MASK,
        ).any { info ->
            val serviceInfo = info.resolveInfo?.serviceInfo ?: return@any false
            serviceInfo.packageName == packageName &&
                serviceInfo.name == FocusBlockerAccessibilityService::class.java.name
        }
    }

    private fun startBlocking(
        blockedApps: List<String>,
        endTimeMillis: Long,
        wholeDevice: Boolean,
    ) {
        val remaining = endTimeMillis - System.currentTimeMillis()
        sharedPreferences.edit().apply {
            putStringSet(BlockingState.PREF_BLOCKED_APPS, blockedApps.toSet())
            putLong(BlockingState.PREF_BLOCK_END_TIME, endTimeMillis)
            putLong(
                BlockingState.PREF_BLOCK_END_ELAPSED,
                SystemClock.elapsedRealtime() + remaining,
            )
            putBoolean(BlockingState.PREF_IS_BLOCKING_ACTIVE, true)
            putBoolean(BlockingState.PREF_DAILY_SCHEDULE_ENABLED, false)
            remove(BlockingState.PREF_DAILY_SCHEDULE_START)
            remove(BlockingState.PREF_DAILY_SCHEDULE_END)
            putBoolean(BlockingState.PREF_WHOLE_DEVICE_MODE, wholeDevice)
            putBoolean(BlockingState.PREF_DEVICE_LOCK_REQUESTED, false)
            apply()
        }

        startBlockingService(
            Intent(this, AppBlockingService::class.java).apply {
                action = AppBlockingService.ACTION_START_BLOCKING
                putStringArrayListExtra("blocked_apps", ArrayList(blockedApps))
                putExtra("end_time", endTimeMillis)
            },
        )
    }

    private fun startDailySchedule(
        blockedApps: List<String>,
        startMinutes: Int,
        endMinutes: Int,
    ) {
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

        startBlockingService(
            Intent(this, AppBlockingService::class.java).apply {
                action = AppBlockingService.ACTION_START_DAILY_SCHEDULE
                putStringArrayListExtra("blocked_apps", ArrayList(blockedApps))
                putExtra("start_minutes", startMinutes)
                putExtra("end_minutes", endMinutes)
            },
        )
    }

    private fun startBlockingService(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopBlocking() {
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
        // stopService is safe from any process state (unlike startService with a
        // stop action, which is blocked for background apps on Android 8+).
        stopService(Intent(this, AppBlockingService::class.java))
    }

    private fun clearFailedBlockingState() {
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
    }

    private fun isBlockingActive(): Boolean = BlockingState.isSessionActive(sharedPreferences)

    private fun getBlockingStatus(): Map<String, Any> {
        val now = System.currentTimeMillis()
        val dailyEnabled = sharedPreferences.getBoolean(
            BlockingState.PREF_DAILY_SCHEDULE_ENABLED,
            false,
        )
        val blockedApps = sharedPreferences
            .getStringSet(BlockingState.PREF_BLOCKED_APPS, emptySet())
            ?.toList() ?: emptyList()

        if (dailyEnabled) {
            val start = sharedPreferences.getInt(BlockingState.PREF_DAILY_SCHEDULE_START, 0)
            val end = sharedPreferences.getInt(BlockingState.PREF_DAILY_SCHEDULE_END, 0)
            val isActive = BlockingState.isWithinDailyWindow(
                BlockingState.currentMinutes(now),
                start,
                end,
            )
            val boundary = BlockingState.nextDailyBoundary(now, start, end)
            return mapOf(
                "isActive" to isActive,
                "timeLeftMillis" to (boundary - now).coerceAtLeast(0L),
                "endTimeMillis" to boundary,
                "blockedApps" to blockedApps,
            )
        }

        val isActive = BlockingState.hasActiveOneShotSession(sharedPreferences)
        val timeLeft = if (isActive) BlockingState.remainingSessionMillis(sharedPreferences) else 0L
        return mapOf(
            "isActive" to isActive,
            "timeLeftMillis" to timeLeft,
            "endTimeMillis" to sharedPreferences.getLong(
                BlockingState.PREF_BLOCK_END_TIME,
                0L,
            ),
            "blockedApps" to blockedApps,
        )
    }

    private companion object {
        const val REQUEST_NOTIFICATIONS = 1001
    }
}
