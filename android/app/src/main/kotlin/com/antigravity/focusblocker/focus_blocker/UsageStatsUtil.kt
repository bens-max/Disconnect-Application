package com.antigravity.focusblocker.focus_blocker

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Process
import android.util.Log

/**
 * Utility class for handling usage stats and app information
 */
object UsageStatsUtil {
    
    private const val TAG = "UsageStatsUtil"
    
    /**
     * Gets the currently focused app package name using UsageStatsManager
     * This is more reliable than AccessibilityService for some Android versions
     */
    fun getForegroundApp(context: Context): String? {
        return try {
            val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val endTime = System.currentTimeMillis()
            val startTime = endTime - 1000 // Get events from past second
            
            val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
            val events = mutableListOf<UsageEvents.Event>()
            
            val event = UsageEvents.Event()
            while (usageEvents.getNextEvent(event)) {
                events.add(event)
            }
            
            // Get the last foreground event
            events.filter { it.eventType == UsageEvents.Event.ACTIVITY_RESUMED }
                .maxByOrNull { it.timeStamp }
                ?.className
                ?.substringBefore("/")
        } catch (e: Exception) {
            Log.e(TAG, "Error getting foreground app", e)
            null
        }
    }
    
    /**
     * Checks if usage stats permission is granted
     */
    fun hasUsageStatsPermission(context: Context): Boolean {
        return try {
            val appOpsManager = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOpsManager.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.e(TAG, "Error checking usage stats permission", e)
            false
        }
    }
    
    /**
     * Gets app display name from package name
     */
    fun getAppDisplayName(context: Context, packageName: String): String {
        return try {
            val packageManager = context.packageManager
            val applicationInfo: ApplicationInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(applicationInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }
    
    /**
     * Gets all installed apps with their package names and display names
     */
    fun getAllInstalledApps(context: Context): List<AppInfo> {
        val packageManager = context.packageManager
        val apps = mutableListOf<AppInfo>()
        
        try {
            val packages = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
            for (appInfo in packages) {
                // Skip system apps unless they're important
                if (appInfo.flags and ApplicationInfo.FLAG_SYSTEM == 0 || 
                    appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP != 0) {
                    val name = appInfo.loadLabel(packageManager).toString()
                    apps.add(AppInfo(appInfo.packageName, name))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting installed apps", e)
        }
        
        return apps.sortedBy { it.displayName }
    }
    
    /**
     * Data class for app information
     */
    data class AppInfo(
        val packageName: String,
        val displayName: String
    )
}
