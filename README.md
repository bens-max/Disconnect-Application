# Disconnect

Disconnect is a local-only Android focus timer built with Flutter. It helps you
step away from distracting apps by returning you to the home screen when you
open an app you chose to block, or by re-locking the screen during a
whole-device session.

There are no accounts, no analytics and no network permissions in the release
build. All session data stays in the app's private storage.

## Features

- One-time focus sessions (hours + minutes).
- Repeating daily schedule, including windows that cross midnight.
- Block selected apps, or lock the whole device for a one-time session.
- Persistent low-priority notification with a system-rendered countdown.
- Session recovery after reboot or app update.
- A clearly visible "End daily schedule" escape hatch. One-time sessions are
  deliberately not cancellable from inside the app.

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

Release build:

```bash
flutter build apk --release
```

The release build currently uses the debug signing key (see the TODO in
`android/app/build.gradle.kts`). Configure a real signing key before publishing.

## How it works

```
Flutter UI (lib/)
  ├─ TimerScreen          duration, scope and entry points
  ├─ ScheduleScreen       daily from/to window
  ├─ AppSelectionScreen   launchable-app picker
  └─ ActiveLockScreen     live status, permission disclosure, schedule exit
          │ MethodChannel "com.antigravity.focusblocker/native"
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
          └─ BootCompletedReceiver
               re-anchors the countdown and restores an unfinished session
```

The native foreground service is the authority for an active session. Flutter
preferences are used by the UI for the app picker and schedule form; on launch
the app re-reads native state so a stale Flutter timer cannot keep the app on
the lock screen.

The foreground service does not tick. The notification uses Android's
chronometer, and one delayed Handler callback fires when the session or the
daily window boundary is reached. While a session is idle the app performs no
periodic work.

## Permissions

Declared in `android/app/src/main/AndroidManifest.xml`:

- `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_SPECIAL_USE` — session service.
- `POST_NOTIFICATIONS` — the persistent session notification on Android 13+.
- `RECEIVE_BOOT_COMPLETED` — restore a session after reboot.
- Accessibility service binding is declared on the service itself; it is not a
  normal `uses-permission`.

`QUERY_ALL_PACKAGES` and `REQUEST_DELETE_PACKAGES` are explicitly removed from
the merged manifest. Package visibility is limited to launchable apps (plus
Flutter's `PROCESS_TEXT` query), which is all the app picker needs.

## Privacy

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
  kiosk mode; safe mode, recovery and OEM-specific shortcuts remain outside the
  app's control.
- The app picker currently hides preinstalled (system) apps. On many phones that
  includes Chrome and some social apps. Showing system apps safely is on the
  roadmap.
- A daily schedule needs the foreground service to be alive. It is restored at
  boot, after an app update, and whenever the app is opened; aggressive OEM
  battery managers may still delay a restart.
- Release signing is not configured yet.

## Documentation

- [`REVIEW_REPORT.md`](REVIEW_REPORT.md) — review findings, lag measurements,
  doc-claim audit, test checklist and roadmap.
- `SYSTEM_ARCHITECTURE.md`, `ANDROID_NATIVE_IMPLEMENTATION_GUIDE.md`,
  `QUICK_DEVELOPER_REFERENCE.md` and `SETUP_AND_NEXT_STEPS.md` are historical
  design notes. They contain claims that were never implemented (for example a
  `BlockingActivity` countdown screen and a 1-second service timer). Treat this
  README and the code as the source of truth.
