# Disconnect Android lag and code review

Review date: 2026-11-08; final verification: 2026-11-12. Branch: `fix/review-and-lag`.
Baseline commit: `3196ae0`. Fix commits: `e535a6b`, `4efc112`, `c39b633`, `f5a8545`, plus the test-tracking and report commits listed at the end.

Measurement environment: Android 14 emulator (API 34, `google_apis`, x86_64, AVD `disconnect-test`, headless SwiftShader), Flutter 3.44.1 / Dart 3.12.1, Linux host. No physical phone or OEM ROM was available.

## Executive summary

- **Most likely root cause of the system-wide lag:** the accessibility service was configured to receive every window change (including `TYPE_WINDOWS_CHANGED`), retrieve window content and interactive windows, and filter every hardware key event. It only needs the foreground package name. Android therefore did extra work for this app on every window and key event across the device.
- **Second confirmed cause:** `AppBlockingService` ran a `java.util.Timer` every second. In daily mode it wrote `is_blocking_active` to SharedPreferences every second and called `NotificationManager.notify()` every second, and the notification channel was `IMPORTANCE_HIGH` with vibration and lights.
- **Also fixed:** a whole-device screen-on path started a foreground service from a broadcast without calling `startForeground()` on that path (Android 8+ background-start failure); the whole-device allowlist did not exempt Settings, IMEs, the phone/dialer, or the user's actual launcher; broad/unused permissions and an exported legacy activity were present.
- **Measured on the emulator:** accessibility capabilities dropped from 9 to 0; event types from `TYPE_WINDOW_STATE_CHANGED + TYPE_WINDOWS_CHANGED` to only `TYPE_WINDOW_STATE_CHANGED`; process CPU over 120 s dropped from 0.24 CPU-seconds to 0 (`<0.01 CPU-s`); notification importance dropped from 4 (HIGH) to 2 (LOW), vibration/lights off, and the notification text stopped changing every second.
- **Not proven:** the exact percentage reduction in accessibility events and the effect on another app's frame jank. The post-fix counter run was interrupted when the test host restarted, so those numbers are left as "not measured" rather than inferred.
- **Top other findings:** duplicate Flutter/native session state; notification-permission denial not surfaced; daily schedule keeps a foreground service alive all day; Handler-based expiry does not fire during deep sleep; legacy `BlockingActivity` is dead code; the app picker hides preinstalled apps; tests and release signing are incomplete.

## What the code actually does

`main()` initializes the native MethodChannel, reads Flutter-side app/schedule/session preferences, asks the native layer for the authoritative active status, and restores a saved daily schedule if one exists (`lib/main.dart:8-58`). The timer form saves duration/scope and opens `ActiveLockScreen` (`lib/screens/timer_screen.dart:73-122`). The picker loads launchable apps without icons, then lazily fetches icons for at most 40 apps in batches (`lib/screens/app_selection_screen.dart:36-102`).

`ActiveLockScreen` shows an accessibility disclosure, checks this app's accessibility service through the native channel, starts a one-time or daily session, and refreshes native status on resume (`lib/screens/active_lock_screen.dart:54-75`, `129-209`, `262-287`). Its 1 Hz countdown updates only a `ValueNotifier` read by a small `ValueListenableBuilder`; the timer is cancelled in `dispose()` (`lib/screens/active_lock_screen.dart:216-287`, `357-363`, `427-438`).

`MainActivity` is the MethodChannel endpoint. It validates requests, writes native preferences, starts/stops `AppBlockingService`, checks accessibility with `AccessibilityManager`, and requests `POST_NOTIFICATIONS` on Android 13+ (`android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/MainActivity.kt:31-138`, `140-153`, `214-238`).

`AppBlockingService` owns the session and notification. It does not tick: it uses `NotificationCompat` with `setUsesChronometer(true)`, `setChronometerCountDown(true)` and `setWhen(endTime)` so SystemUI renders the countdown, and schedules one `Handler` callback for the next session end or daily boundary (`AppBlockingService.kt:21-28`, `198-227`, `250-308`). The channel is `IMPORTANCE_LOW`, silent, no vibration/lights; the old high-importance channel is deleted (`AppBlockingService.kt:315-334`). `BootCompletedReceiver` re-anchors elapsed time using the wall-clock end time and restarts a still-valid session (`BootCompletedReceiver.kt:14-78`). `ScreenOnReceiver` no longer starts a service; during whole-device mode it asks the already-connected accessibility service to lock, or sets a flag for the next connection (`ScreenOnReceiver.kt:18-39`).

`FocusBlockerAccessibilityService` is event-driven. The XML and `setServiceInfo` request only `TYPE_WINDOW_STATE_CHANGED`, `feedbackGeneric`, `flagDefault`, `canRetrieveWindowContent=false`, no key filtering, and a 100 ms timeout (`android/app/src/main/res/xml/accessibility_service_config.xml:8-14`; `FocusBlockerAccessibilityService.kt:144-150`). Values are cached in memory and refreshed only by `OnSharedPreferenceChangeListener` (`FocusBlockerAccessibilityService.kt:117-130`, `199-219`). The hot path returns immediately for non-state events, debounces the same package for 500 ms, exempts this app, system UI, Settings, launchers, IMEs, dialers and `android`, then calls `performGlobalAction(GLOBAL_ACTION_HOME)` or `GLOBAL_ACTION_LOCK_SCREEN` (`FocusBlockerAccessibilityService.kt:164-192`, `61-115`, `236-244`). It does not launch `BlockingActivity`.

## Documentation claims versus implementation

| Document claim | Reality and evidence |
|---|---|
| `SYSTEM_ARCHITECTURE.md` describes a 500 ms `BlockingActivity` countdown, HOME/BACK key interception and window content events (historical sections around lines 53-75 and 186-275). | Historical only. `BlockingActivity` is unexported and never started; it still has empty `onBackPressed`/`onKeyDown` overrides (`AndroidManifest.xml:61-66`; `BlockingActivity.kt:100-112`). The service receives only `TYPE_WINDOW_STATE_CHANGED` and never overrides `onKeyEvent` (`accessibility_service_config.xml:9`; `FocusBlockerAccessibilityService.kt:144-150`). |
| Architecture/implementation guides say the foreground service checks every second and updates the notification continuously; the blocking screen refreshes every 500 ms. | Not current. The service has no timer loop and updates the notification only on start/state boundary (`AppBlockingService.kt:198-227`, `250-308`). `BlockingActivity` has no countdown implementation. The documents now carry historical-design banners. |
| Architecture performance table gives CPU/memory/battery percentages and calls the app production-ready. | Never measured; no physical-device data. The banner now says the tables are unmeasured. Release signing still uses the debug key (`android/app/build.gradle.kts:33-38`). |
| Guides list `BIND_ACCESSIBILITY_SERVICE`, `QUERY_ALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`, `PACKAGE_USAGE_STATS` and `DISABLE_KEYGUARD` as manifest permissions. | True for the baseline commit, false now. `BIND_ACCESSIBILITY_SERVICE` belongs on the service element; the broad permissions and `REQUEST_DELETE_PACKAGES` are removed (`AndroidManifest.xml:21-26`, `75-85`). The current release merged manifest contains only `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS` and `RECEIVE_BOOT_COMPLETED` (plus AndroidX's generated receiver permission). |
| Flows say accessibility reads SharedPreferences on every event and the foreground service prevents force-stop. | The current service reads preferences only on connection/change. A foreground service does **not** prevent force-stop; `README.md:107-123` now says so. |
| `SETUP_AND_NEXT_STEPS.md` says minimum API 26 and lists the plugin accessibility service. | Actual merged manifest is minSdk 24; the plugin is removed and only the custom service remains. The setup guide is now labelled historical. |
| `QUICK_DEVELOPER_REFERENCE.md` lists the earlier file set and a 1-second blocking timer. | Historical; the banners point readers to `README.md` and this report. |
| README says the release build has no network permission. | Verified in the release merged manifest: no `INTERNET`. The debug manifest does include `INTERNET` from Flutter's debug manifest. Release signing and store policy are still unverified. |

## Findings

| ID | Severity | Confidence | File:line | What is wrong | Why it matters | Fix | Status |
|---|---|---|---|---|---|---|---|
| F1 | High | Confirmed | `android/app/src/main/res/xml/accessibility_service_config.xml:9-12` (current); baseline `3196ae0` config | Baseline requested `typeWindowsChanged` in addition to state changes, `canRetrieveWindowContent=true`, `canRequestFilterKeyEvents=true`, and flags including interactive windows, not-important views, web accessibility, view IDs and IME. | Android did extra accessibility/input work on every window and key event system-wide; this is a plausible direct cause of the "app is slowing down your phone" warning. | Only `typeWindowStateChanged`, generic feedback, default flags, no content retrieval, no key filtering. | Fixed (`e535a6b`) |
| F2 | High | Confirmed | Baseline `FocusBlockerAccessibilityService.kt` in `3196ae0`; current `FocusBlockerAccessibilityService.kt:144-166` | Baseline service also registered `TYPE_WINDOW_STATE_CHANGED \| TYPE_WINDOWS_CHANGED`, with `FLAG_RETRIEVE_INTERACTIVE_WINDOWS \| FLAG_REQUEST_FILTER_KEY_EVENTS` and a 50 ms timeout. | Every additional window event woke the app's main thread; key filtering adds synchronous input latency. The block decision only needs the package name. | One event type, flags 0, 100 ms timeout, in-memory state. | Fixed (`e535a6b`) |
| F3 | High | Confirmed | Baseline `AppBlockingService.kt:213-233`, `255-335` | A `Timer` ran every second. In daily mode it wrote `is_blocking_active` every second and called `notify()` every second; the channel was `IMPORTANCE_HIGH` with vibration and lights. | Continuous wakeups and SystemUI notification rebuilds while idle; visible countdown changed every second and could buzz/light the screen. | Removed the loop; system chronometer; one Handler callback; low-importance silent channel; old channel deleted. | Fixed (`e535a6b`) |
| F4 | High | Confirmed | Baseline `AndroidManifest.xml:2-17`, `51-56`; current `AndroidManifest.xml:21-26`, `61-66` | Baseline requested `BIND_ACCESSIBILITY_SERVICE` as a uses-permission, plus `QUERY_ALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`, `PACKAGE_USAGE_STATS` and `DISABLE_KEYGUARD`; `BlockingActivity` was exported. | Incorrect permission model, unnecessary Play review burden and a launchable legacy activity that other apps could open. | Removed the uses-permissions; binding is on the service; `QUERY_ALL_PACKAGES`/`REQUEST_DELETE_PACKAGES` removed with `tools:node="remove"`; legacy activity unexported. | Fixed (`e535a6b`) |
| F5 | High | Confirmed | Baseline `FocusBlockerAccessibilityService.kt:34-47`; current `FocusBlockerAccessibilityService.kt:61-115`, `184` | Baseline whole-device allowlist was a short hard-coded launcher list. It did not include Settings, enabled IMEs, the phone/dialer, the default dialer or an OEM launcher not in the list. | A whole-device session could lock the user out of the home screen, keyboard, Settings (the only place to disable the service) or emergency calling. | Added `android`, Settings, phone/dialer/emergency, permission/package installers; resolves all HOME activities, enabled IMEs and the default dialer at runtime. | Fixed; user-editable exemptions remain roadmap (`e535a6b`) |
| F6 | High | Confirmed | Baseline `ScreenOnReceiver.kt`; baseline `AppBlockingService.kt:45-72` | Screen-on called `startForegroundService(ACTION_RELOCK_SCREEN)`; that branch called `relockScreenIfNeeded()` but never `startForeground()` within the 5 s limit. | On Android 8+, starting this path from a background broadcast can fail with an ANR/crash and never re-lock. | Removed the service start; the receiver uses the connected accessibility service, or sets a flag consumed on the next connection (`ScreenOnReceiver.kt:18-39`). | Fixed (`e535a6b`) |
| F7 | Medium | Confirmed | `lib/services/storage_service.dart:3-67`; `lib/screens/active_lock_screen.dart:129-209` | Flutter stores selected apps, end time, schedule and whole-device mode separately from native preferences; native is authoritative only for active status. | State can drift after native expiry, force-stop, update or partial failure; the UI can show stale setup data. | Native active status is now the source of truth; next step is a native repository/API for selection and schedule too. | Partially fixed; migration proposed |
| F8 | Medium | Confirmed | `MainActivity.kt:130-138`; `ActiveLockScreen` status card | `POST_NOTIFICATIONS` is requested at startup, but denial is never surfaced or used to gate a session. | On Android 13+ the foreground service runs with no visible notification, reducing transparency and user trust. | Add a health/status row and explain that the session still runs but the notification is hidden. | Proposed |
| F9 | Medium | Confirmed | `AppBlockingService.kt:108-129`, `221-227` | A daily schedule starts a foreground service immediately and keeps it alive all day, including outside the focus window; the notification says "Next block starts at …". | A persistent foreground service and notification all day is avoidable battery/UX cost and can trigger OEM battery heuristics. | Stop the service outside the window and re-arm with an alarm/WorkManager, or keep the FGS only while blocking is active. | Proposed |
| F10 | Medium | Likely | `AppBlockingService.kt:216-227`; `BlockingState.kt:70-81` | Expiry uses `Handler.postDelayed`, which is based on uptime and does not advance during deep sleep; the accessibility service uses elapsed realtime and stops blocking correctly, but the service/notification cleanup can be late. | A session can look active in the notification after it has actually expired, and the FGS can stay alive longer than needed. | Add an `AlarmManager`/WorkManager backstop and reconcile on wake/screen-on. | Proposed |
| F11 | Low | Confirmed | `BlockingState.kt:25-28`; `FocusBlockerAccessibilityService.kt:221-234` | In daily mode every window-state event calls `currentMinutes()`, which allocates a `Calendar`. | Small per-event allocation on the main thread; not the primary cause, but unnecessary in the hot path. | Cache the current window/boundary or compare epoch millis without `Calendar` per event. | Proposed |
| F12 | Medium | Confirmed | `BlockingActivity.kt:16-112`; `AndroidManifest.xml:61-66` | The legacy full-screen activity remains in source and the manifest but is never launched; it contains obsolete BACK/HOME overrides and a fullscreen flag. | Dead code misleads maintainers and can be accidentally reconnected. | Remove it, or deliberately rebuild a blocking screen with a lifecycle-aware countdown. | Proposed |
| F13 | Medium | Confirmed | `lib/screens/app_selection_screen.dart:39-42` | `InstalledApps.getInstalledApps(excludeSystemApps: true)` hides preinstalled apps. | Chrome, YouTube and some social apps are preinstalled on many phones and cannot be selected, which defeats the main use case. | Offer a "show system apps" filter that still excludes non-launchable packages; document the trade-off. | Proposed |
| F14 | Medium | Confirmed | `test/widget_test.dart:14-32`; `test/schedule_test.dart:6-54` | Only 8 Dart tests exist (2 widget, 6 schedule); there are no Android unit/instrumented tests for session expiry, exemptions, debounce or reboot recovery. | The native hot path and session edge cases have no automated regression protection. | Add native tests and an instrumentation/manual suite; keep the schedule tests tracked in git. | Partially fixed; native tests proposed |
| F15 | Low | Confirmed | `android/app/build.gradle.kts:22-30`, `41-49`; `pubspec.yaml:37-38` | The app uses application id `com.antigravity.focusblocker.focus_blocker` while the product is Disconnect and the Dart package is `focus_blocker`; the Gradle file has a duplicated `androidx.core` dependency. | Identity is confusing and the duplicate dependency is noise; renaming an installed app id is a migration, not a safe cleanup. | Document identity; remove the duplicate dependency; rename only with a migration plan. | Proposed |
| F16 | Low | Confirmed | `android/app/build.gradle.kts:33-38`; `android/app/src/main/kotlin/.../UsageStatsUtil.kt:15` | Release builds still use the debug signing key, and `UsageStatsUtil` is unused (and its `getForegroundApp` returns a class name, not a package). | Cannot publish safely; dead utility may mislead future work. | Configure release signing; remove or implement usage stats behind a permission flow. | Proposed |
| F17 | Low | Confirmed | `.gitignore` (baseline of this review); `test/schedule_test.dart` | A `/test/` ignore rule excluded the schedule tests from git, so CI would only see the widget tests. | The test suite was not actually versioned; future clones would silently lose coverage. | Removed `/test/` from `.gitignore` and added `test/schedule_test.dart`. | Fixed in this review |
| F18 | Low | Confirmed | `FocusBlockerAccessibilityService.kt:246-259` | Reading `Settings.Secure.ENABLED_INPUT_METHODS` directly threw `SecurityException` on targetSdk 36 during emulator testing. | Opening the service could crash the app and disable blocking. | Use `InputMethodManager.enabledInputMethodList` instead. | Fixed (`e535a6b`) |
| F19 | Low | Confirmed | `AppBlockingService.kt:250-308` (`formatTime`), daily boundary logic | Daily boundary math uses the default time zone and there is no `ACTION_TIME_CHANGED`/`ACTION_TIMEZONE_CHANGED` receiver. | After a time-zone or manual clock change, the next boundary can be wrong until the app/service is restarted. | Add a time-change receiver and reconcile the boundary. | Proposed |
| F20 | Low | Confirmed | `pubspec.yaml:37-38` (`installed_apps`, `shared_preferences_android`) | Flutter warns that these plugins apply the Kotlin Gradle Plugin and will fail in future Flutter versions. | The build works now but will break on a future Flutter upgrade. | Migrate when plugin versions support Built-in Kotlin. | Proposed |

## Lag investigation

| Hypothesis | Verdict | Evidence and quantification |
|---|---|---|
| **H1 Event firehose** | **Confirmed as the primary event-volume cause** | Baseline XML requested `typeWindowsChanged\|typeWindowStateChanged`; the service also set both event types. After the fix, `dumpsys accessibility` shows only `TYPE_WINDOW_STATE_CHANGED`. A debug counter measured **182 events in one 60 s interval** containing 40 SETTINGS/HOME cycles (26 s workload) on the baseline. The post-fix counter run was interrupted by a test-host restart, so the percentage drop is **not measured**; the configuration itself removes the extra `TYPE_WINDOWS_CHANGED` stream. |
| **H2 Expensive capabilities** | **Confirmed and removed** | Baseline `canRetrieveWindowContent=true` and flags included `flagRetrieveInteractiveWindows`, `flagIncludeNotImportantViews`, `flagRequestEnhancedWebAccessibility`, `flagReportViewIds` and `flagInputMethodEditor`; `dumpsys accessibility` reported `capabilities=9`. Current config is `canRetrieveWindowContent=false`, `flagDefault`, no node/window traversal; the emulator reported `capabilities=0`. |
| **H3 Key-event filtering** | **Confirmed and removed** | Baseline requested `canRequestFilterKeyEvents=true` and `FLAG_REQUEST_FILTER_KEY_EVENTS`; every hardware key event was routed through the service. Current service has no key filtering and no `onKeyEvent`; the emulator config showed `capabilities=0`. |
| **H4 Work per event** | **Confirmed reduced; residual cost remains** | The baseline already cached preferences in a listener, so per-event SharedPreferences reads were not the cause at `3196ae0`. The current hot path still converts `event.packageName` to a string, does a debounce comparison and a set lookup; daily mode also allocates a `Calendar` via `currentMinutes()` (F11). The event-path cost was not timed with `System.nanoTime`; no mean-duration claim is made. |
| **H5 Ticking service** | **Confirmed and removed** | Baseline `scheduleAtFixedRate(..., 0, 1000)` wrote prefs every second in daily mode and called `notify()` every second; channel importance was HIGH with vibration/lights. Current code has one `Handler` callback at the boundary and a system-rendered chronometer. Measured notification: importance 4 → 2, vibration/lights enabled → disabled, text changed every 4 s → unchanged after 4 s, fixed `when` + chronometer after the fix. |
| **H6 Activity launch loop** | **Ruled out** | The current service never starts `BlockingActivity`; it calls `GLOBAL_ACTION_HOME` or `GLOBAL_ACTION_LOCK_SCREEN`. The baseline also used the global actions from the accessibility service, so there was no activity relaunch loop to count. |
| **H7 Duplicate accessibility services / plugin overhead** | **Ruled out in the delivered build** | The plugin is removed from `pubspec.yaml`; the merged release manifest contains exactly one app accessibility service. The plugin's own manifest had no `<service>` declaration and its `performGlobalAction` depended on a listener that was never registered, so it was inert at baseline and is now gone. |
| **H8 Memory pressure** | **Not verified** | Baseline process RSS was 52,224 KB; after the fix it was 86,324 KB, but the post-fix process was a fresh app with a warm Flutter engine, so the numbers are not comparable. No low-RAM device or `dumpsys meminfo` comparison was possible. |
| **H9 OEM behaviour** | **Likely** | The event firehose, key filtering, 1 Hz notification rebuild and high-importance vibration are exactly the kind of wakeup/CPU/notification churn that OEM battery/performance heuristics flag. The emulator cannot reproduce a Xiaomi/Realme/Oppo/Vivo/Samsung system warning; the physical-device test remains required. |

### Root-cause assessment

The strongest explanation for the reported system-wide lag is **H1 + H2 + H3 + H5**: an over-privileged accessibility service and a foreground service that rebuilt a high-importance notification every second. The service only needs `event.packageName` from a single event type, yet the baseline asked Android to deliver every window change and every key event with window-content capabilities. On a busy phone that means constant main-thread callbacks, input-path work and SystemUI notification rebuilds. The measured CPU and notification changes support the removal; the event-count and other-app-jank percentages are not claimed because those runs did not complete.

### Before/after measurements

| Metric | Baseline (`3196ae0`) | After (`fix/review-and-lag`) | How measured |
|---|---:|---:|---|
| Accessibility event types | `TYPE_WINDOW_STATE_CHANGED` + `TYPE_WINDOWS_CHANGED` | `TYPE_WINDOW_STATE_CHANGED` only | `adb shell dumpsys accessibility` |
| Accessibility capabilities | 9 | 0 | `adb shell dumpsys accessibility` |
| Notification timeout | 50 ms | 100 ms | `adb shell dumpsys accessibility` |
| Accessibility events during a 60 s interval with 40 SETTINGS/HOME cycles | 182 | Not captured (run interrupted) | Debug-only counter in the service, read with `adb logcat -s FocusBlockerA11y` |
| App CPU while idle with a session, 120 s | 0.24 CPU-s (24 ticks) | `<0.01 CPU-s` (0 ticks) | Process `utime+stime` sampled over 120 s |
| Notification importance | 4 (HIGH) | 2 (LOW) | `adb shell dumpsys notification --noredact` |
| Notification vibration/lights | enabled | disabled | `adb shell dumpsys notification --noredact` |
| Notification text/update | `Apps blocked for 00:14:44` → `00:14:40` after 4 s | `Selected apps are blocked`, unchanged after 4 s | Notification dumps and screenshots |
| Daily notification | n/a in this measurement | `Disconnect is blocking apps` / `Blocked until 8:55 PM`, importance 2, fixed `when` | Notification dump |
| Process RSS | 52,224 KB | 86,324 KB | `dumpsys meminfo`; **not comparable** (different process state) |
| Other-app jank p90/p95/p99 | Not measured | Not measured | Need `dumpsys gfxinfo` with and without a session on a physical device |
| Blocked-app interception | Not re-run | Verified: launching `com.google.android.deskclock` returned to `com.google.android.apps.nexuslauncher` | `adb shell am start` + `dumpsys activity` |
| Active UI with native session | Crash risk from input-method enumeration | App opened and showed `Blocking active for 1 app(s)` + countdown | Emulator screenshot |

Acceptance criteria from the brief: the **CPU-idle**, **no-per-second-notify** and **blocking-still-works** criteria are met on the emulator. The **≥90% event drop** and **no measurable jank** criteria are **not established** because the after-counter and frame-jank runs did not complete; the exact commands are in the test section.

## Improvement roadmap

| Priority | Improvement | Impact | Effort | Risk |
|---|---|---|---|---|
| P0 | Re-run the event counter and `gfxinfo` on a physical phone (including a Xiaomi/Realme/Samsung if possible), with and without a session | High | S | Low; measurement only |
| P1 | Native single-source session repository; remove duplicated Flutter end-time/schedule fields | High | M | Medium; migration and restart edge cases |
| P1 | Health screen: accessibility, notification permission, FGS state and service-loss warning | High | M | Medium; OS/OEM differences |
| P1 | Stop the daily FGS outside the window; add an AlarmManager/WorkManager backstop for expiry and boundaries | High | M | Medium; exact-alarm/FGS restrictions |
| P1 | Make essential-app exemptions user-editable (Phone, Messages, Maps, banking) | High | M | Medium; whole-device lockout safety |
| P1 | Verify `specialUse` policy, configure release signing, and test Android 14/15 boot-start rules | High | S | Medium; store/platform policy |
| P2 | "Most used apps" suggestions via UsageStatsManager with an explicit opt-in/explanation | Medium | M | Medium; sensitive special access |
| P2 | Daily per-app budgets, local-only statistics, profiles (Study/Work/Sleep) | High | L | Medium; data retention/design |
| P2 | Gentle/strict friction modes and bounded emergency unlocks | Medium | M | Medium; product semantics |
| P3 | Quick Settings tile/widget; opt-in notification muting via NotificationListenerService | Medium | L | High; extra permission/service |
| P3 | Show system apps in the picker; remove dead `BlockingActivity`/`UsageStatsUtil`; fix app identity | Medium | S/M | Low |
| P3 | Dark-mode/a11y/localization polish and bundled fonts (already removed runtime `google_fonts`) | Medium | M | Low |
| P3 | Keep CI on analyze/test/debug build and add Android instrumentation tests | Medium | M | Low |

## Manual test checklist and ADB commands

1. Install the debug APK on Android 7/API 24 and a current Android 14/15/16 phone; record build, API and OEM.
2. Start a selected-app session with accessibility off. Confirm the disclosure names package-name access, opens Accessibility settings, and the screen says blocking is inactive.
3. Enable the service; open a blocked app and confirm it returns Home within ~300 ms. Open unblocked apps, Disconnect, Settings, launcher, keyboard, phone and emergency dialer and confirm they are not blocked.
4. Run whole-device mode; turn the screen off/on and confirm re-lock, safe unlock, Settings reachable and the service can be disabled.
5. Start a short session; replace it, stop/expire it; verify notification and state cleanup. Change the clock both ways and verify the running timer uses elapsed realtime.
6. Start a daily schedule crossing midnight; verify before/start/inside/end/next day; test timezone and DST changes.
7. Reboot during a one-time session and a daily schedule; test app update recovery; force-stop and confirm honest UI after reopening.
8. Deny notifications on Android 13+; disable/re-enable accessibility mid-session; observe status and notification channel importance/sound/chronometer.
9. Scroll a heavy app for 60 s with and without a session; capture CPU, events, frame stats, logs, battery stats and memory.
10. Test empty app set, zero/negative duration, invalid schedule, expired session on reboot and starting a second session while one is active.

Commands used or recommended:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell pm grant com.antigravity.focusblocker.focus_blocker android.permission.POST_NOTIFICATIONS
adb shell settings put secure enabled_accessibility_services \
  com.antigravity.focusblocker.focus_blocker/com.antigravity.focusblocker.focus_blocker.FocusBlockerAccessibilityService
adb shell dumpsys accessibility
adb shell dumpsys notification --noredact | grep -A8 -i disconnect
adb shell dumpsys meminfo com.antigravity.focusblocker.focus_blocker
adb shell dumpsys cpuinfo | grep -i focusblocker
adb shell dumpsys batterystats --charged com.antigravity.focusblocker.focus_blocker
adb logcat -s FocusBlockerA11y
adb shell am start -a android.settings.SETTINGS
adb shell input keyevent 3
adb shell dumpsys activity activities | grep -i mResumedActivity
adb shell dumpsys gfxinfo OTHER_APP reset
# scroll OTHER_APP for 60 s, then:
adb shell dumpsys gfxinfo OTHER_APP
```

For a controlled event-rate comparison, run 40 `SETTINGS` + Home cycles and read the debug counter's next 60-second log. The baseline produced 182 events in that interval; repeat the identical sequence on the fixed APK and on a physical phone.

## Build and check evidence

Commands run on 2026-11-12:

- `flutter --version` → Flutter 3.44.1 stable, Dart 3.12.1.
- `flutter analyze` → `No issues found! (ran in 2.3s)`.
- `flutter test` → `00:01 +8: All tests passed!` (2 widget tests + 6 schedule tests).
- `flutter build apk --debug` → `✓ Built build/app/outputs/flutter-apk/app-debug.apk`; Gradle assembleDebug 6.4 s; APK 168,918,657 bytes.
- `./gradlew :app:processReleaseMainManifest` → `BUILD SUCCESSFUL in 2s`; release merged manifest contains no `INTERNET`, `QUERY_ALL_PACKAGES`, `REQUEST_DELETE_PACKAGES`, `SYSTEM_ALERT_WINDOW`, `PACKAGE_USAGE_STATS` or `DISABLE_KEYGUARD`.
- `git diff --check` → no whitespace errors.
- Build warning: Flutter reports that the app and the `installed_apps` / `shared_preferences_android` plugins apply the Kotlin Gradle Plugin and may fail in a future Flutter version; current build succeeds.

## Known limitations and unverified items

- **No physical-device measurements.** Everything in the measurement table is from the Android 14 API 34 `google_apis` x86_64 emulator. A Xiaomi/Realme/Oppo/Vivo/Samsung battery or performance warning cannot be reproduced there.
- **The post-fix event count and other-app jank percentage are not measured.** The counter run was interrupted by the test-host restart. The commands above reproduce them; do not treat the configuration change as a measured 90% event reduction.
- **RSS is not comparable.** The after run included a warm Flutter engine; no low-RAM/memory-pressure conclusion is drawn.
- **Daily schedules keep the foreground service alive all day** even outside the window; expiry cleanup uses a Handler that does not fire during deep sleep (F9, F10).
- **Time-zone/clock changes** are not handled by a receiver; the elapsed-time authority protects a running session, but the next daily boundary can be wrong after a manual clock change.
- **Force-stop defeats background work** until the app is opened again; a foreground service cannot prevent this.
- **Release signing uses the debug key**, and `specialUse` foreground-service policy approval is unverified.
- **Flutter and native state remain duplicated** for selected apps/schedule; native active status is authoritative, but the setup fields are not fully consolidated.
- **The picker hides preinstalled apps** (`excludeSystemApps: true`), so Chrome and some social apps may be missing.
- **No Android instrumentation tests**; the 8 Dart tests cover startup and schedule math only.
- **Direct boot/LOCKED_BOOT** is not supported; preferences are credential-protected.
- **The plugin removal is not a Play-policy review.** AccessibilityService use still requires a prominent disclosure and policy justification.

## Commits on `fix/review-and-lag`

- `e535a6b` — `fix: reduce Android background work during sessions`
- `4efc112` — `feat: improve session setup and native state sync`
- `c39b633` — `docs: record verified behavior and lag review`
- `f5a8545` — `ci: add Flutter checks and ignore build artifacts`
- `221aadd` — `fix: track schedule tests in git`
- The report update is the final commit on the branch.
