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
                    startBlocking(blockedApps, endTimeMillis)
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

    private fun startBlocking(blockedApps: List<String>, endTimeMillis: Long) {
        // Save blocking data to SharedPreferences
        sharedPreferences.edit().apply {
            putStringSet("blocked_apps_native", blockedApps.toSet())
            putLong("block_end_time", endTimeMillis)
            putBoolean("is_blocking_active", true)
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

    private fun stopBlocking() {
        sharedPreferences.edit().apply {
            putBoolean("is_blocking_active", false)
            putStringSet("blocked_apps_native", emptySet())
            apply()
        }

        val serviceIntent = Intent(this, AppBlockingService::class.java)
        stopService(serviceIntent)
    }

    private fun isBlockingActive(): Boolean {
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
