package com.antigravity.focusblocker.focus_blocker

import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.provider.Settings
import android.content.ComponentName
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val NATIVE_CHANNEL = "com.antigravity.focusblocker/native"
    private lateinit var sharedPreferences: SharedPreferences

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        sharedPreferences = getSharedPreferences("com.antigravity.focusblocker.focus_blocker", MODE_PRIVATE)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    // Initialize native components
                    result.success(true)
                }
                "isAccessibilityServiceEnabled" -> {
                    result.success(isAccessibilityServiceEnabled())
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
                        result.error("SERVICE_PERMISSION", "Foreground service permission was denied", e.message)
                    } catch (e: IllegalStateException) {
                        clearFailedBlockingState()
                        result.error("SERVICE_START_FAILED", "Foreground service could not be started", e.message)
                    }
                }
                "requestDeviceLock" -> {
                    sharedPreferences.edit().putBoolean("device_lock_requested", true).apply()
                    result.success(true)
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
                                startMinutes != endMinutes
                        ) {
                            "Daily schedule times must be different valid times"
                        }
                        startDailySchedule(blockedApps, startMinutes, endMinutes)
                        result.success(true)
                    } catch (e: IllegalArgumentException) {
                        result.error("INVALID_SCHEDULE_REQUEST", e.message, null)
                    } catch (e: SecurityException) {
                        clearFailedBlockingState()
                        result.error("SERVICE_PERMISSION", "Foreground service permission was denied", e.message)
                    } catch (e: IllegalStateException) {
                        clearFailedBlockingState()
                        result.error("SERVICE_START_FAILED", "Foreground service could not be started", e.message)
                    }
                }
                "stopBlocking" -> {
                    stopBlocking()
                    result.success(true)
                }
                "isBlockingActive" -> {
                    val isActive = isBlockingActive()
                    result.success(isActive)
                }
                "getBlockingStatus" -> {
                    val status = getBlockingStatus()
                    result.success(status)
                }
                else -> result.notImplemented()
            }
        }

    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val expectedService = ComponentName(
            this,
            FocusBlockerAccessibilityService::class.java,
        ).flattenToString()
        return enabledServices.split(':').any {
            it.equals(expectedService, ignoreCase = true)
        }
    }

    private fun startBlocking(
        blockedApps: List<String>,
        endTimeMillis: Long,
        wholeDevice: Boolean,
    ) {
        // Save blocking data to SharedPreferences
        sharedPreferences.edit().apply {
            putStringSet("blocked_apps_native", blockedApps.toSet())
            putLong("block_end_time", endTimeMillis)
            putBoolean("is_blocking_active", true)
            remove("daily_schedule_start")
            remove("daily_schedule_end")
            putBoolean("daily_schedule_enabled", false)
            putBoolean("whole_device_mode", wholeDevice)
            putBoolean("device_lock_requested", false)
            apply()
        }

        // Start the blocking service
        val serviceIntent = Intent(this, AppBlockingService::class.java).apply {
            action = AppBlockingService.ACTION_START_BLOCKING
            putStringArrayListExtra("blocked_apps", ArrayList(blockedApps))
            putExtra("end_time", endTimeMillis)
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun startDailySchedule(
        blockedApps: List<String>,
        startMinutes: Int,
        endMinutes: Int,
    ) {
        sharedPreferences.edit().apply {
            putStringSet("blocked_apps_native", blockedApps.toSet())
            putInt("daily_schedule_start", startMinutes)
            putInt("daily_schedule_end", endMinutes)
            putBoolean("daily_schedule_enabled", true)
            putBoolean("is_blocking_active", true)
            apply()
        }

        val serviceIntent = Intent(this, AppBlockingService::class.java).apply {
            action = AppBlockingService.ACTION_START_DAILY_SCHEDULE
            putStringArrayListExtra("blocked_apps", ArrayList(blockedApps))
            putExtra("start_minutes", startMinutes)
            putExtra("end_minutes", endMinutes)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopBlocking() {
        sharedPreferences.edit().apply {
            putBoolean("is_blocking_active", false)
            putStringSet("blocked_apps_native", emptySet())
            remove("daily_schedule_enabled")
            remove("daily_schedule_start")
            remove("daily_schedule_end")
            putBoolean("whole_device_mode", false)
            putBoolean("device_lock_requested", false)
            apply()
        }

        val serviceIntent = Intent(this, AppBlockingService::class.java)
        serviceIntent.action = AppBlockingService.ACTION_STOP_BLOCKING
        startService(serviceIntent)
    }

    private fun clearFailedBlockingState() {
        sharedPreferences.edit().apply {
            putBoolean("is_blocking_active", false)
            putStringSet("blocked_apps_native", emptySet())
            remove("block_end_time")
            remove("daily_schedule_enabled")
            remove("daily_schedule_start")
            remove("daily_schedule_end")
            putBoolean("whole_device_mode", false)
            putBoolean("device_lock_requested", false)
            apply()
        }
    }

    private fun isBlockingActive(): Boolean {
        if (sharedPreferences.getBoolean("daily_schedule_enabled", false)) {
            val start = sharedPreferences.getInt("daily_schedule_start", 0)
            val end = sharedPreferences.getInt("daily_schedule_end", 0)
            val calendar = java.util.Calendar.getInstance()
            val current = calendar.get(java.util.Calendar.HOUR_OF_DAY) * 60 +
                    calendar.get(java.util.Calendar.MINUTE)
            return if (start < end) {
                current >= start && current < end
            } else {
                current >= start || current < end
            }
        }
        val endTime = sharedPreferences.getLong("block_end_time", 0L)
        val isActive = sharedPreferences.getBoolean("is_blocking_active", false)
        return isActive && endTime > System.currentTimeMillis()
    }

    private fun getBlockingStatus(): Map<String, Any> {
        val endTime = sharedPreferences.getLong("block_end_time", 0L)
        val isActive = isBlockingActive()
        val timeLeft = if (isActive) endTime - System.currentTimeMillis() else 0L
        val blockedApps = sharedPreferences.getStringSet("blocked_apps_native", emptySet())?.toList() ?: emptyList()
        
        return mapOf(
            "isActive" to isActive,
            "timeLeftMillis" to timeLeft,
            "endTimeMillis" to endTime,
            "blockedApps" to blockedApps
        )
    }
}
