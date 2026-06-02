# Focus Blocker - Setup & Next Steps

## 🚀 Getting Started

This guide will help you set up and verify the complete native Android integration for the Focus Blocker app.

## ✅ Pre-Implementation Checklist

- [x] Flutter project created with accessibility service support
- [x] Android minimum SDK: API 26 (Android 8.0)
- [x] Kotlin configured in project
- [x] SharedPreferences available

## 📋 Step 1: Verify Implementation Files

### Check that all files are in place:

**Kotlin Files (Android):**
```
android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/
├── MainActivity.kt ✓
├── FocusBlockerAccessibilityService.kt ✓
├── AppBlockingService.kt ✓
├── BlockingActivity.kt ✓
├── BootCompletedReceiver.kt ✓
└── UsageStatsUtil.kt ✓
```

**Dart Files:**
```
lib/
├── main.dart ✓
├── services/
│   ├── native_service.dart ✓
│   └── storage_service.dart ✓
└── screens/
    └── active_lock_screen.dart ✓
```

**Config Files:**
```
android/app/src/main/
├── AndroidManifest.xml ✓
└── res/xml/
    └── accessibility_service_config.xml ✓
```

## 🔧 Step 2: Build & Compile

### Clean build (recommended for first-time setup):

```bash
cd d:\Softwares\Projects

# Clean previous builds
flutter clean

# Rebuild Flutter deps
flutter pub get

# Build APK for testing
flutter build apk
```

### Expected output:
```
✓ Built d:\Softwares\Projects\build\app\outputs\flutter-apk\app-release.apk
```

## 📱 Step 3: Install on Device/Emulator

### Install the app:
```bash
flutter install
# or
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Verify installation:
```bash
adb shell pm list packages | grep focus_blocker
# Output: package:com.antigravity.focusblocker.focus_blocker
```

## 🔐 Step 4: Enable Accessibility Service

**Manual (User Perspective):**
1. Open device Settings
2. Navigate to: Accessibility (or Settings → System → Accessibility)
3. Look for "Focus Blocker" in the list
4. Toggle it **ON**
5. Grant permissions when prompted

**Programmatic (In App):**
The app automatically prompts when needed:
```dart
// app checks and shows dialog if not enabled
bool isEnabled = await FlutterAccessibilityService
    .isAccessibilityPermissionEnabled();

if (!isEnabled) {
  await FlutterAccessibilityService.requestAccessibilityPermission();
}
```

**Verify in shell:**
```bash
adb shell settings get secure enabled_accessibility_services
# Should contain: com.antigravity.focusblocker.focus_blocker/...FocusBlockerAccessibilityService
```

## 🧪 Step 5: Test Basic Blocking

### Manual Test Procedure:

1. **Start the app**
   ```bash
   flutter run
   ```

2. **Select apps to block**
   - Open "App Selection Screen"
   - Select a test app (e.g., Chrome, Firefox, Settings)
   - Set duration to 2 minutes
   - Tap "Start Blocking"

3. **Verify blocking UI appears**
   - Should see "Active Lock Screen"
   - Timer should count down
   - "Accessibility Service enabled" message
   - "Native blocking activated for X app(s)"

4. **Test blocking action**
   - Try opening the blocked app
   - Should see "BlockingActivity" full-screen
   - Shows app name and timer
   - Try back button → goes to home
   - Try home button → goes to home

5. **Wait for expiry or stop manually**
   - Either wait 2 minutes for auto-expire
   - Or tap "Stop Blocking" button

### Expected Results:
- ✅ Blocking screen appears when blocked app opened
- ✅ Timer counts down accurately
- ✅ Back/home buttons redirected to home screen
- ✅ Foreground notification visible while blocking
- ✅ Auto-stop when time expires

## 🔍 Step 6: Verify All Components

### Check Accessibility Service is registered:
```bash
adb shell dumpsys accessibility | grep focus_blocker
# Should show the service is enabled
```

### Check Foreground Service notification:
```bash
adb shell dumpsys notification | grep "Focus Blocker"
# Should show notification with timer
```

### Check SharedPreferences data:
```bash
adb shell cat /data/data/com.antigravity.focusblocker.focus_blocker/shared_prefs/*.xml
# Should show blocked_apps_native and block_end_time
```

### Check logcat for errors:
```bash
adb logcat | grep -i focus
# Look for: "FocusBlockerAccessibilityService", "AppBlockingService", etc.
```

## 🎯 Step 7: Test Edge Cases

### Test 1: Multiple App Blocking
- [ ] Block 3-5 apps simultaneously
- [ ] Verify all are blocked
- [ ] Try different app combinations

### Test 2: Device Reboot During Blocking
- [ ] Start blocking
- [ ] Boot device (adb reboot)
- [ ] After reboot, blocking should still be active
- [ ] Try opening blocked app

### Test 3: App Crash
- [ ] Start blocking
- [ ] Kill app: adb shell am force-stop com.antigravity.focusblocker.focus_blocker
- [ ] Reopen app
- [ ] Blocking should still be active

### Test 4: Accessibility Service Disable
- [ ] Start blocking
- [ ] Disable service in Settings
- [ ] Try opening blocked app
- [ ] Should NOT block (expected)
- [ ] Enable service again and verify blocking works

### Test 5: Time Expiry
- [ ] Block for 1 minute
- [ ] Wait for expiry
- [ ] After timer expires, blocked app should open normally

## 📊 Performance Verification

### Battery Drain Test
- Monitor device battery percentage
- Run blocking for 1 hour
- Check if under 5% drain

### Memory Usage
```bash
adb shell ps -o name,rss | grep focus_blocker
# Check memory usage < 30MB
```

### CPU Usage
```bash
adb shell top -n 1 | grep focus_blocker
# Check CPU % is minimal when idle
```

## 🐛 Debugging

### Enable verbose logging:

**MainActivity.kt:**
```kotlin
Log.d("FocusBlocker", "MethodChannel call: ${call.method}")
```

**FocusBlockerAccessibilityService.kt:**
```kotlin
override fun onAccessibilityEvent(event: AccessibilityEvent?) {
    Log.d("FocusBlocker", "Event: ${event?.packageName}, Type: ${event?.eventType}")
}
```

### Run with logs:
```bash
adb logcat -c
flutter run
# Then observe output
```

### Full debug output:
```bash
adb logcat -d > debug_log.txt
# Search for "FocusBlocker", "ERROR", "Exception"
```

## ✨ Common Issues & Solutions

### Issue: "Accessibility Service not enabled"
**Solution:**
1. Check: Settings → Accessibility → Focus Blocker
2. Ensure it's toggled ON
3. If missing, reinstall app: `flutter install`

### Issue: Blocking activity doesn't appear
**Solution:**
1. Verify AccessibilityService is receiving events:
   - `adb logcat | grep FocusBlockerAccessibilityService`
2. Check that BlockingActivity is exported:
   - `adb shell dumpsys package com.antigravity.focusblocker.focus_blocker | grep BlockingActivity`
3. Try with different app (some apps may not trigger accessibility events)

### Issue: Foreground notification doesn't update
**Solution:**
1. Ensure notification channel is created
2. Check Android version (13+ requires POST_NOTIFICATIONS permission)
3. Verify foreground service is running:
   - `adb shell dumpsys activity services | grep AppBlockingService`

### Issue: Blocking stops after device reboot
**Solution:**
1. Verify BootCompletedReceiver is exported=true
2. Check RECEIVE_BOOT_COMPLETED permission exists
3. Ensure blocking end time hasn't already passed

### Issue: Build fails with "Cannot find symbol"
**Solution:**
1. Clean: `flutter clean`
2. Get dependencies: `flutter pub get`
3. Rebuild: `flutter build apk`
4. Check imports in Kotlin files are correct

## 📚 Next Steps for Enhancement

### Phase 2 - Polish & Features
- [ ] Add app icon to blocking activity
- [ ] Add motivational messages/quotes
- [ ] Customize colors per user preference
- [ ] Add app usage statistics

### Phase 3 - Advanced Features
- [ ] Schedule blocking sessions
- [ ] Create app categories
- [ ] Set recurring block times
- [ ] Add emergency override code
- [ ] Family control/parental override

### Phase 4 - Analytics & Insights
- [ ] Track blocking sessions
- [ ] Statistics dashboard
- [ ] Most blocked apps analysis
- [ ] Focus time tracking
- [ ] Weekly/monthly reports

### Phase 5 - Integration
- [ ] Desktop/web dashboard
- [ ] Cloud sync across devices
- [ ] Family mode management
- [ ] Integration with calendar apps
- [ ] Notification filtering

## 📞 Module Documentation

Once implemented, detailed docs are available in:

1. **ANDROID_NATIVE_IMPLEMENTATION_GUIDE.md**
   - Complete architecture overview
   - Detailed component descriptions
   - Communication flows
   - Permission requirements
   - Testing recommendations
   - Troubleshooting guide

2. **QUICK_DEVELOPER_REFERENCE.md**
   - Quick lookup for files
   - Common modifications
   - Debugging tips
   - Performance considerations
   - Version compatibility

## ✅ Verification Checklist

Before considering implementation complete:

- [ ] All Kotlin files compile without errors
- [ ] All Dart files compile without errors
- [ ] AndroidManifest.xml has all required permissions
- [ ] Accessibility service configuration is correct
- [ ] Dependencies in build.gradle.kts are added
- [ ] App installs on device/emulator
- [ ] Accessibility service can be enabled
- [ ] Blocking session starts successfully
- [ ] BlockingActivity appears when blocked app opened
- [ ] Timer counts down properly
- [ ] Foreground notification updates in real-time
- [ ] Blocking expires automatically
- [ ] Blocking persists after app restart
- [ ] Blocking recovers after device reboot
- [ ] No crashes or exceptions in logcat
- [ ] Battery drain is within acceptable limits

## 🎉 Success Criteria

Your implementation is successful when:

1. ✅ **Detection**: System reliably detects blocked app launches
2. ✅ **Prevention**: Users cannot access blocked apps during session
3. ✅ **Persistence**: Blocking survives app restarts and device reboots
4. ✅ **Timing**: Timer and expiry work accurately
5. ✅ **UX**: Blocking screen and notifications are smooth and intuitive
6. ✅ **Stability**: No crashes, exceptions, or memory leaks
7. ✅ **Performance**: Minimal battery and CPU impact

## 📞 Support Resources

### Official Documentation
- [Android Accessibility Service Docs](https://developer.android.com/guide/topics/accessibility/accessibility-overview)
- [Flutter MethodChannel](https://flutter.dev/docs/development/platform-integration/platform-channels)
- [Android Foreground Services](https://developer.android.com/guide/components/foreground-services)

### Project Structure
- Guide: `ANDROID_NATIVE_IMPLEMENTATION_GUIDE.md`
- Reference: `QUICK_DEVELOPER_REFERENCE.md`
- This file: `SETUP_AND_NEXT_STEPS.md`

## 📝 Notes

- Always test on real devices (emulator may have different behavior)
- Different Android versions may have slight variations
- Accessibility service permissions are sensitive; handle carefully
- Time-based logic depends on device system time accuracy
- Persistent services may be affected by Doze mode on some devices

---

**Last Updated:** April 24, 2026
**Implementation Status:** ✅ Complete
**Testing Status:** Ready for QA
