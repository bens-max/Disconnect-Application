# Focus Blocker - Native Android Integration Guide

## Overview

This document provides a complete implementation guide for the Focus Blocker app's native Android integration. The solution uses Android's Accessibility Service, Usage Stats, MethodChannel communication between Flutter and Android, a Foreground Service for persistence, and a custom Blocking Activity.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter App (UI Layer)                   │
│  main.dart, active_lock_screen.dart, app_selection_screen   │
└──────────────────────┬──────────────────────────────────────┘
                       │ MethodChannel
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Native Service (Kotlin)                     │
│  native_service.dart <-> MainActivity.kt (MethodChannel)    │
└──────────────────┬──────────────────┬──────────────────────┘
                   │                  │
         ┌─────────▼──────┐    ┌──────▼──────────┐
         │ Accessibility   │    │  Foreground      │
         │ Service         │    │  Service         │
         │ (Detection)     │    │  (Persistence)   │
         └────┬────────────┘    └──────┬──────────┘
              │                        │
              └────────────┬───────────┘
                           │
                    ┌──────▼─────────┐
                    │ Blocking        │
                    │ Activity        │
                    │ (UI Lock)       │
                    └─────────────────┘
```

## Components Implemented

### 1. **MainActivity.kt** (MethodChannel Integration)
- Handles communication between Flutter and native Android
- Manages `startBlocking`, `stopBlocking`, `isBlockingActive`, `getBlockingStatus` methods
- Stores blocking configuration in SharedPreferences
- Starts/stops AppBlockingService

**Key Methods:**
- `startBlocking()`: Initializes blocking session with package names and end time
- `stopBlocking()`: Terminates blocking and cleanup
- `isBlockingActive()`: Returns current blocking state
- `getBlockingStatus()`: Provides real-time blocking information

### 2. **FocusBlockerAccessibilityService.kt** (App Detection)
- Custom Accessibility Service that monitors app launches in real-time
- Detects when blocked apps come to foreground
- Launches BlockingActivity when blocked app is detected
- Handles key events (attempts to intercept home button)
- Updates blocking state from SharedPreferences continuously

**Key Capabilities:**
- Monitors `TYPE_WINDOW_STATE_CHANGED` and `TYPE_WINDOW_CONTENT_CHANGED` events
- Can retrieve window content for detailed app detection
- Attempts to intercept home button (device-dependent)
- Retrieves currently focused app package name

### 3. **AppBlockingService.kt** (Foreground Service)
- Runs as persistent foreground service to ensure blocking continuity
- Displays notification with remaining blocking time
- Automatically expires blocking when time runs out
- Survives activity recreation and temporary app suspension
- Updates SharedPreferences to coordinate with AccessibilityService

**Key Features:**
- `ACTION_START_BLOCKING`: Initiates blocking with app list and duration
- `ACTION_STOP_BLOCKING`: Cleanly stops the service
- Timer-based expiration checking (every 1 second)
- Real-time notification updates
- HIGH priority for reliability

### 4. **BlockingActivity.kt** (Blocking Screen)
- Full-screen activity shown when blocked app is launched
- Prevents user from accessing the blocked app
- Displays countdown timer
- Provides "Return to Home" button
- Overrides back button and home button handling
- Shows app name that's blocked
- Window flags prevent users from circumventing

**Features:**
- `FLAG_FULLSCREEN`: Hides system UI
- `FLAG_DISMISS_KEYGUARD`: Shows over lock screen
- `FLAG_SHOW_WHEN_LOCKED`: Visible on lock screen
- `FLAG_TURN_SCREEN_ON`: Brings screen on
- Overridden `onKeyDown()` for back/home button handling
- Automatic timer countdown with 500ms update rate

### 5. **BootCompletedReceiver.kt** (Persistence After Reboot)
- Receives `BOOT_COMPLETED` intent
- Restores blocking session if still active after device restart
- Prevents data loss if user reboots device mid-blocking

### 6. **UsageStatsUtil.kt** (App Monitoring Utilities)
- Helper methods for app detection and permission checking
- Gets foreground app using UsageStatsManager (alternative to AccessibilityService)
- Checks if PACKAGE_USAGE_STATS permission is granted
- Lists all installed apps
- Translates package names to display names

## Communication Flow

### Starting a Blocking Session

```
User selects apps and duration:
    ↓
AppSelectionScreen.dart
    ↓
storage_service.saveBlockedApps() + saveEndTime()
    ↓
NativeService.startBlocking() [MethodChannel call]
    ↓
MainActivity.kt::startBlocking()
    ├─ Saves data to SharedPreferences
    └─ Starts AppBlockingService
        ├─ Starts foreground with notification
        ├─ Begins timer for expiration
        └─ Updates SharedPreferences
    
    Meanwhile, FocusBlockerAccessibilityService:
    ├─ Reads from SharedPreferences
    ├─ Monitors for app launches
    └─ Launches BlockingActivity when blocked app detected
```

### When a Blocked App is Opened

```
User attempts to open blocked app
    ↓
FocusBlockerAccessibilityService detects TYPE_WINDOW_STATE_CHANGED
    ↓
Check if package is in blocked_apps_native set
    ↓
Verify blocking is still active (check end time)
    ↓
Launch BlockingActivity with package name and end time
    ↓
BlockingActivity displays full-screen
    ├─ Shows app name being blocked
    ├─ Shows countdown timer
    └─ Overrides back/home buttons
```

## Permissions Required

```xml
<!-- Core Permissions -->
<uses-permission android:name="android.permission.BIND_ACCESSIBILITY_SERVICE" />
<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" />
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />

<!-- For time verification -->
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" />

<!-- For Foreground Service -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" /> <!-- Android 13+ -->

<!-- For Boot Recovery -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<!-- For Screen Control -->
<uses-permission android:name="android.permission.DISABLE_KEYGUARD" />
```

## Android Manifest Entries

### Accessibility Service
```xml
<service
    android:name=".FocusBlockerAccessibilityService"
    android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
    android:exported="false">
    <intent-filter>
        <action android:name="android.accessibilityservice.AccessibilityService" />
    </intent-filter>
    <meta-data
        android:name="android.accessibilityservice"
        android:resource="@xml/accessibility_service_config" />
</service>
```

### Foreground Service
```xml
<service
    android:name=".AppBlockingService"
    android:exported="false" />
```

### Blocking Activity
```xml
<activity
    android:name=".BlockingActivity"
    android:exported="true"
    android:launchMode="singleInstance"
    android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen"
    android:excludeFromRecents="true"
    android:showOnLockScreen="true" />
```

### Boot Receiver
```xml
<receiver
    android:name=".BootCompletedReceiver"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
    </intent-filter>
</receiver>
```

## Dart Integration

### NativeService.dart
Provides Flutter-level interface to native methods:

```dart
// Start blocking
await NativeService.startBlocking(blockedAppsList, endTime);

// Stop blocking
await NativeService.stopBlocking();

// Check if active
bool isActive = await NativeService.isBlockingActive();

// Get status
BlockingStatus status = await NativeService.getBlockingStatus();
```

### main.dart
- Initializes NativeService on app startup
- Checks for active blocking session
- Routes to appropriate screen

### active_lock_screen.dart
- Calls `NativeService.startBlocking()` when user starts blocking
- Displays UI status and updates
- Handles accessibility permission requests
- Provides manual stop option

## Data Persistence

### SharedPreferences Keys
```kotlin
"blocked_apps_native"      // Set<String> of package names
"block_end_time"           // Long milliseconds since epoch
"is_blocking_active"       // Boolean blocking state
```

These are synchronized between:
- Flutter app (stored separately)
- MainActivity (MethodChannel layer)
- AccessibilityService (detection logic)
- AppBlockingService (persistence and expiration)

## Security & Reliability Features

### 1. **Time-Based Verification**
- All blocking checks verify `blockEndTime > System.currentTimeMillis()`
- Uses system time (not device-relative)
- Persists across app restarts

### 2. **Multi-Layer Detection**
- AccessibilityService: Real-time app launch detection
- Foreground Service: Continuous operation assurance
- Blocking Activity: UI-level enforcement
- Fallback to home button action

### 3. **Resilience**
- Survives app crashes or force-close
- Persists after device reboot
- Recovery via BootCompletedReceiver
- Automatic expiration when time ends

### 4. **User Bypass Prevention**
- Blocking Activity overrides back button
- Attempts to intercept home button
- Full-screen display mode
- Shows over lock screen

### 5. **Data Consistency**
- Single source of truth in SharedPreferences
- Read before every decision
- Service-to-service synchronization
- Atomic operations where possible

## Installation & Setup Instructions

### 1. **Gradle Dependencies**
Ensure `build.gradle.kts` includes:
```kotlin
dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.core:core:1.12.0")
}
```

### 2. **Accessibility Service Configuration**
File: `android/app/src/main/res/xml/accessibility_service_config.xml`

Includes:
- `canRetrieveWindowContent="true"` - to get package names
- `canRequestFilterKeyEvents="true"` - to intercept key events
- `flagRetrieveInteractiveWindows` - window access
- Notification timeout set to 100ms for responsiveness

### 3. **String Resource**
Ensure `android/app/src/main/res/values/strings.xml` contains:
```xml
<string name="accessibility_service_description">
    This service is used to monitor app launches and block selected apps during focus sessions.
</string>
```

### 4. **Permissions Handling at Runtime**

**Accessibility Permission:**
```dart
// Check if enabled
bool isEnabled = await FlutterAccessibilityService
    .isAccessibilityPermissionEnabled();

// Request if not enabled
await FlutterAccessibilityService
    .requestAccessibilityPermission();
```

**Usage Stats Permission:**
- Must be manually enabled in Settings → Apps → Special app access → Usage access
- Check with `UsageStatsUtil.hasUsageStatsPermission()` if needed

**Post Notifications Permission (Android 13+):**
- Requested via pubspec.yaml or permission_handler package
- Or handled by foreground service notification

## Testing Recommendations

### 1. **Basic Functionality**
- [ ] Accessibility service successfully enables
- [ ] Start blocking with 1-2 minute duration
- [ ] Verify foreground notification appears
- [ ] Open a blocked app → Blocking activity shows
- [ ] Verify timer counts down
- [ ] Block expires automatically
- [ ] Secondary blocking attempt works

### 2. **Edge Cases**
- [ ] Device reboot during blocking → still active
- [ ] App crashes → blocking persists
- [ ] Multiple app attempts during blocking
- [ ] Back button while in blocking activity
- [ ] Home button while in blocking activity
- [ ] Volume buttons while in blocking activity

### 3. **Accessibility Service**
- [ ] Service shows in Accessibility Settings
- [ ] Can be enabled/disabled manually
- [ ] Re-enables properly after disable
- [ ] Works with other accessibility apps

### 4. **Performance**
- [ ] Minimal battery drain
- [ ] No excessive logging
- [ ] Smooth UI transitions
- [ ] Timely app detection

## Troubleshooting

### Issue: Blocking Activity doesn't appear
**Solution:**
1. Verify Accessibility Service is enabled: Settings → Accessibility → Focus Blocker
2. Check logcat for "FocusBlockerAccessibilityService" messages
3. Ensure BlockingActivity is properly exported in manifest
4. Test with simple app like Firefox

### Issue: Blocking stops working after app close
**Solution:**
1. AppBlockingService should restart automatically
2. If not, verify Foreground Service permissions on Android 12+
3. Check notification channel creation

### Issue: Doesn't persist after reboot
**Solution:**
1. Verify `RECEIVE_BOOT_COMPLETED` permission in manifest
2. Ensure BootCompletedReceiver is exported=true
3. Check that blocking was still within time window

### Issue: Timer not accurate
**Solution:**
1. Use `System.currentTimeMillis()` consistently
2. Remember: Device time might be skewed; verify user's device time
3. All expiry checks compare against system time

## Best Practices

1. **Always verify blocking is still active before taking action**
   - Check `blockEndTime > System.currentTimeMillis()`
   - Read from SharedPreferences to get latest state

2. **Use SharedPreferences as source of truth**
   - Multiple components access it
   - Ensures consistency across services

3. **Handle permissions explicitly**
   - Show dialogs for missing permissions
   - Guide users to system settings

4. **Log important events**
   - Service start/stop
   - Blocking start/stop
   - App blocking attempts
   - Foreground app detection

5. **Clean up resources**
   - Cancel timers in onDestroy
   - Unsubscribe from streams
   - Remove handlers/callbacks

## Advanced Customization

### Custom Blocking UI
Modify `BlockingActivity.kt` to:
- Show different messages per app
- Add motivational quotes
- Display app usage statistics
- Include custom animations

### Additional Checks
Enhance `FocusBlockerAccessibilityService.kt` with:
- Whitelisted system apps that bypass blocking
- Time-based override codes
- Multiple blocking sessions
- Priority-based app grouping

### Analytics
Add tracking for:
- Blocking session duration
- Most blocked apps
- Bypass attempts
- Successful focus sessions

## References

- [Android Accessibility Service Documentation](https://developer.android.com/guide/topics/accessibility/accessibility-overview)
- [Usage Stats Manager](https://developer.android.com/reference/android/app/usage/UsageStatsManager)
- [Foreground Services](https://developer.android.com/guide/components/foreground-services)
- [Flutter MethodChannel](https://flutter.dev/docs/development/platform-integration/platform-channels)
- [Android SharedPreferences](https://developer.android.com/training/data-storage/shared-preferences)

## Summary

This implementation provides a robust, multi-layered approach to app blocking:

✅ **Real-time Detection**: Accessibility Service monitors app launches instantly
✅ **Persistent Execution**: Foreground Service keeps blocking alive
✅ **Reliable Blocking**: BlockingActivity prevents access + home screen redirect
✅ **User-Proof**: Multiple layers prevent bypass attempts
✅ **Device Reboot Safe**: BootCompletedReceiver restores sessions
✅ **Time-Based Expiry**: Automatic cleanup when duration ends
✅ **Flutter Integration**: MethodChannel provides clean Dart interface
✅ **Modern Android**: Supports Android 8.0+ with proper API usage

The solution balances functionality, reliability, and user experience while respecting Android's design guidelines for sensitive permissions like Accessibility Service.
