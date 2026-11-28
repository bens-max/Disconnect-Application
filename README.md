# Disconnect

Disconnect is a local-only Android focus timer built with Flutter. It helps you
step away from distracting apps by returning you to the home screen when you
open an app you chose to block, or by re-locking the screen during a
whole-device session.

There are no accounts, no analytics and no network permissions in the release
build. All session data stays in the app's private storage.

## Features

- One-time focus sessions (hours + minutes).
- Multiple weekly schedules, including windows that cross midnight.
- Block selected apps, or lock the whole device for a one-time session.
- Configure always-allowed apps that remain available in every blocking mode.
- Whole-device sessions are limited to 12 hours and require Android 9 (API 28)
  or newer.
- Active sessions can be paused for five minutes up to four times per local
  calendar day across all sessions; blocking then resumes automatically.
- Persistent low-priority notification with a system-rendered countdown.
- Session recovery after reboot or app update.
- A clearly visible "End schedule(s)" escape hatch. One-time sessions are
  not endable from inside the app, but can be paused for five minutes.

## Requirements

- Flutter 3.44+ with Dart 3.11+.
- Android 7.0 (API 24) or newer.
- The Disconnect accessibility service must be enabled by the user. Android
  does not allow an app to grant this permission itself.

## Build and run

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Then open Disconnect, start a session, and enable the service when the app asks
(or use Settings → Accessibility → Disconnect).

## Release signing

Release APKs and app bundles use a dedicated release keystore. The keystore
and its properties file must both live outside this repository; release
packaging fails rather than falling back to Android's debug key.

```bash
mkdir -p "$HOME/.local/share/disconnect/signing" "$HOME/.config/disconnect"
chmod 700 "$HOME/.local/share/disconnect/signing" "$HOME/.config/disconnect"
keytool -genkeypair -v \
  -keystore "$HOME/.local/share/disconnect/signing/release.jks" \
  -alias disconnect -keyalg RSA -keysize 4096 -validity 10000
```

Create `$HOME/.config/disconnect/android-signing.properties` with the following
values, substituting your own absolute path and passwords:

```properties
storeFile=/home/you/.local/share/disconnect/signing/release.jks
storePassword=your-keystore-password
keyAlias=disconnect
keyPassword=your-key-password
```

Restrict the properties file to your user (`chmod 600
$HOME/.config/disconnect/android-signing.properties`), keep secure backups of
both files, and never commit or share them. Build a signed release with:

```bash
export DISCONNECT_SIGNING_PROPERTIES="$HOME/.config/disconnect/android-signing.properties"
flutter build appbundle --release
```

## Application identity

The Android `applicationId` and Kotlin namespace remain
`com.antigravity.focusblocker.focus_blocker` to preserve the ability to update
existing installs. The app label and Flutter package name are `Disconnect` and
`disconnect`; the MethodChannel is `com.disconnect/native`. Native preference
names also retain the legacy ID so existing sessions and app selections remain
readable. Changing the Android ID requires an explicit migration plan and
cannot update an installation under the existing ID.

## How it works

```
Flutter UI (lib/)
  ├─ TimerScreen          duration, scope and entry points
  ├─ ScheduleScreen       daily from/to window
  ├─ AppSelectionScreen   launchable-app picker
  └─ ActiveLockScreen     live status, pause control, permission disclosure
          │ MethodChannel "com.disconnect/native"
          ▼
MainActivity (Kotlin)
  └─ validates requests, writes native prefs, starts/stops the service
          │
          ├─ AppBlockingService (foreground)
          │    owns the session state, shows one notification, and uses a
          │    single Handler callback at the next session/schedule boundary
          │
          ├─ FocusBlockerAccessibilityService
          │    receives only TYPE_WINDOW_STATE_CHANGED, keeps its config in
          │    memory, and calls GLOBAL_ACTION_HOME or GLOBAL_ACTION_LOCK_SCREEN
          │
          ├─ BoundaryReceiver
          │    reconciles exact-alarm boundaries and clock/time-zone changes
          └─ BootCompletedReceiver
               restores all saved windows and re-anchors unfinished sessions
```

The native repository is authoritative for blocked and permitted apps, the
whole-device mode, one-shot session timing, and every schedule window. Flutter
SharedPreferences stores only onboarding completion and app-picker UI filters.
The UI reads current status from the native repository rather than reconciling
duplicate session preferences.

The foreground service is active only during an unpaused one-shot session or
an active schedule window. Boundary reconciliation clears expired sessions and
stops inactive schedule windows without starting a foreground service; it
starts the service only when blocking should be active. An exact `RTC_WAKEUP`
alarm starts/stops it at schedule boundaries; when exact-alarm access is denied
the app logs the downgrade and uses an inexact idle-allowed alarm. A one-shot
expiry alarm also reconciles after deep sleep. The service does not tick;
Android's notification chronometer renders the countdown.

## Permissions

Declared in `android/app/src/main/AndroidManifest.xml`:

- `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_SPECIAL_USE` — session service.
- `POST_NOTIFICATIONS` — the persistent session notification on Android 13+.
- `SCHEDULE_EXACT_ALARM` — precise schedule boundaries and deep-sleep expiry
  reconciliation on Android 12+; the health screen reports and links to this
  setting.
- `RECEIVE_BOOT_COMPLETED` — restore a session after reboot.
- Accessibility service binding is declared on the service itself; it is not a
  normal `uses-permission`.

`QUERY_ALL_PACKAGES` and `REQUEST_DELETE_PACKAGES` are explicitly removed from
the merged manifest. Package visibility is limited to launchable apps (plus
Flutter's `PROCESS_TEXT` query), which is all the app picker needs.

Disconnect uses Android's accessibility service only after the user enables it
in system settings. The service observes foreground package changes to apply
the user's block list; it does not read window content or keystrokes. The
`specialUse` foreground service supports user-started sessions and scheduled
blocking windows, and displays an ongoing notification. Store listings and
Play Console declarations should describe these exact purposes and the
prominent in-app disclosure.

On Android 14+, most new installs targeting Android 13+ do not receive exact
alarm access by default. Disconnect checks `canScheduleExactAlarms()` before
scheduling; without access it degrades to an inexact idle-allowed alarm rather
than using `setAlarmClock()`, which would incorrectly present focus boundaries
as user-facing alarm-clock events. Android 14+ foreground-service types also
require a Play Console declaration; `specialUse` use cases are reviewed, so
the manifest subtype is a description, not store approval. See the [Android
exact-alarm guidance](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)
and [foreground-service type guidance](https://developer.android.com/about/versions/14/changes/fgs-types-required).

## Privacy

Android backup and device transfer are disabled for the application. See the
[Privacy Policy](PRIVACY_POLICY.md) for what is stored locally and how it is
used.

The accessibility service is configured with `canRetrieveWindowContent="false"`,
no key-event filtering and only `typeWindowStateChanged` events. It reads the
package name of the foreground app and compares it with the user's block list.
It never reads screen text, passwords or messages, and it does not transmit
anything.

## Known limitations

- Blocking cannot work while the accessibility service is disabled. The app
  shows that state instead of pretending the session is active.
- Force-stopping the app disables the accessibility service and the foreground
  service until the app is opened again. Android provides no supported way for
  an app to survive a force-stop.
- Whole-device mode re-locks the screen when the display turns on. It is not a
  kiosk mode; an active whole-device session also re-locks when the
  accessibility service reconnects. Safe mode, recovery and OEM-specific
  shortcuts remain outside the app's control.
- The app picker hides system apps by default, but users can enable
  **Show system apps** in its filter controls.
- Exact alarms may be denied or delayed by Android/OEM policy; the health
  screen reports permission status and blocking falls back to inexact alarms.
- Aggressive OEM battery managers can still stop or delay background work.
- Force-stop cannot be recovered automatically by Android; reopening the app
  reconciles saved state and re-arms any remaining schedule.

## Device validation

Emulators cannot reproduce launcher, keyboard, accessibility, emergency-call
or OEM battery-manager differences. Follow the [physical-device checklist](REAL_DEVICE_TEST_CHECKLIST.md)
before release.

## Documentation

- [`REVIEW_REPORT.md`](REVIEW_REPORT.md) — historical review findings and
  measurements; some recorded issues have since been addressed.
- [`REAL_DEVICE_TEST_CHECKLIST.md`](REAL_DEVICE_TEST_CHECKLIST.md) — OEM and
  Android behavior checks that require physical phones.
- `SYSTEM_ARCHITECTURE.md`, `ANDROID_NATIVE_IMPLEMENTATION_GUIDE.md`,
  `QUICK_DEVELOPER_REFERENCE.md` and `SETUP_AND_NEXT_STEPS.md` are historical
  design notes. They contain claims that were never implemented (for example a
  `BlockingActivity` countdown screen and a 1-second service timer). Treat this
  README and the code as the source of truth.
