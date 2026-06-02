package com.antigravity.focusblocker.focus_blocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build

/**
 * Receiver that restarts blocking after device reboot
 */
class BootCompletedReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED && context != null) {
            // Check if blocking is still active after boot
            val sharedPreferences = context.getSharedPreferences(
                "com.antigravity.focusblocker.focus_blocker",
                Context.MODE_PRIVATE
            )
            
            val isBlockingActive = sharedPreferences.getBoolean("is_blocking_active", false)
            val blockEndTime = sharedPreferences.getLong("block_end_time", 0L)
            
            // If blocking was active before reboot and hasn't expired yet, restart it
            if (isBlockingActive && blockEndTime > System.currentTimeMillis()) {
                val blockedApps = sharedPreferences.getStringSet("blocked_apps_native", emptySet())?.toList() ?: emptyList()
                
                val serviceIntent = Intent(context, AppBlockingService::class.java).apply {
                    action = AppBlockingService.ACTION_START_BLOCKING
                    putStringArrayListExtra("blocked_apps", ArrayList(blockedApps))
                    putExtra("end_time", blockEndTime)
                }
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }
        }
    }
}
