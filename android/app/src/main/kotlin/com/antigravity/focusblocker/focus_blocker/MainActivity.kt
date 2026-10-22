package com.antigravity.focusblocker.focus_blocker

import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
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
                "startBlocking" -> {
                    val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                    val endTimeMillis = call.argument<Long>("endTimeMillis") ?: 0L
                    val wholeDevice = call.argument<Boolean>("wholeDevice") ?: false
                    startBlocking(blockedApps, endTimeMillis, wholeDevice)
                    result.success(true)
                }
                "requestDeviceLock" -> {
                    sharedPreferences.edit().putBoolean("device_lock_requested", true).apply()
                    result.success(true)
                }
                "startDailySchedule" -> {
                    val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                    val startMinutes = call.argument<Int>("startMinutes") ?: 0
                    val endMinutes = call.argument<Int>("endMinutes") ?: 0
                    startDailySchedule(blockedApps, startMinutes, endMinutes)
                    result.success(true)
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
        stopService(serviceIntent)
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
