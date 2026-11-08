# Disconnect Android lag and code review

Review date: 2026-11-08. Branch: `fix/review-and-lag`.

## Executive summary

- **Confirmed:** the old accessibility configuration subscribed to window content changes, requested window content and interactive-window data, and requested key-event filtering. The revised config accepts only window-state changes and declines content/key capabilities; the service handles package names in memory.
- **Confirmed:** the former foreground service tick and notification update loop has been replaced by a one-shot `Handler` boundary callback and a system-rendered notification chronometer.
- These changes remove clear sources of unnecessary system-wide event handling and periodic app work. **They do not prove a measured reduction in other apps' jank:** this environment has no connected device/emulator.
- **Confirmed:** `flutter analyze` reports no issues, `flutter test` passes (2 tests), and `flutter build apk --debug` succeeds.
- **Confirmed:** merged manifest has one custom accessibility service, one special-use foreground service and the boot/update receiver; the Flutter accessibility plugin service and broad package permissions are absent.
- **High:** `BlockingActivity` remains in source but is no longer used. Blocked launches go to Home (whole-device sessions request screen lock); the user does not see the documented full-screen countdown wall.
- **High:** Flutter still stores a second copy of session state in `SharedPreferences`; native is treated as authoritative for active status, but the user-selected app list/schedule/duration are also read from Flutter prefs.
- **Medium:** target SDK is 36, while release signing, store policy acceptance for `specialUse`, and device/OEM behavior have not been verified.
- **Medium:** current tests cover two startup form cases only; native session timing, expiry, reboot, permissions, exemptions and real app interception lack automated/device tests.

## What the code actually does

`main()` initializes the MethodChannel, loads app-picker/schedule/session fields from Flutter `SharedPreferences`, then queries native status to choose the initial screen ([main.dart](/home/benson-cherian-suresh/Development/Disconnect-Application/lib/main.dart:8)). `TimerScreen` saves a requested duration/scope and routes to `ActiveLockScreen`; app selection uses `installed_apps`, retrieves launchable app metadata without icons initially, then lazily requests up to 40 icons in batches ([app_selection_screen.dart](/home/benson-cherian-suresh/Development/Disconnect-Application/lib/screens/app_selection_screen.dart:36)). The active screen presents an accessibility disclosure, asks native code whether this app's accessibility service is enabled, starts a one-time session or schedule, and refreshes native status on resume ([active_lock_screen.dart](/home/benson-cherian-suresh/Development/Disconnect-Application/lib/screens/active_lock_screen.dart:34)). Its visible countdown uses a one-second Dart timer; this timer is only active while the Flutter screen is mounted.

`MainActivity` handles `com.antigravity.focusblocker/native`, stores native session values, checks the enabled service via `AccessibilityManager`, requests Android 13+ notification permission, and starts/stops `AppBlockingService` ([MainActivity.kt](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/MainActivity.kt:31)). Native preferences use `BlockingState.PREFS_NAME`; the accessibility service copies relevant values into fields through a preference listener and at service connection ([BlockingState.kt](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/BlockingState.kt:12), [FocusBlockerAccessibilityService.kt](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/FocusBlockerAccessibilityService.kt:117)). The event handler ignores non-window-state events, debounces repeat package names for 500 ms, exempts its package, system, launchers, IMEs and dialers, then sends blocked app launches Home. Whole-device mode invokes the global lock action (or Home before API 28) ([FocusBlockerAccessibilityService.kt](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/FocusBlockerAccessibilityService.kt:164)). It does not launch `BlockingActivity`.

`AppBlockingService` promotes itself to foreground, displays a low-importance silent notification with a system chronometer, and schedules one callback for session/schedule boundary. It does not poll each second; daily schedules re-arm at each boundary. `BootCompletedReceiver` re-anchors elapsed time on boot and starts the service for a still-valid session ([AppBlockingService.kt](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/AppBlockingService.kt:55), [BootCompletedReceiver.kt](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/BootCompletedReceiver.kt:14)). The active session expiry uses elapsed realtime while running and persisted wall time for reboot recovery.

## Documentation claims versus implementation

| Document claim | Reality and evidence |
|---|---|
| `SYSTEM_ARCHITECTURE.md` describes real-time content/window events, key interception and launching `BlockingActivity` (e.g. lines 53–75, 186–275). | Historical only. Config accepts `typeWindowStateChanged`; service sets `flags=0`, never overrides `onKeyEvent`, and calls `performGlobalAction` ([XML](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/res/xml/accessibility_service_config.xml:8), [service](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/FocusBlockerAccessibilityService.kt:144)). Manifest labels `BlockingActivity` legacy/unlaunched ([manifest](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/AndroidManifest.xml:56)). README and the architecture document’s new notice now disclose this. |
| Architecture/implementation guides say service timer checks each second, notification updates continuously, and activity updates each 500 ms (architecture lines 282–304, 464–514; guide lines 71–100). | Not current behavior. Service only schedules a boundary callback and updates notification on state/boundary ([AppBlockingService.kt](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/AppBlockingService.kt:198)); `BlockingActivity` has no timer implementation. Historical guides now warn readers in their opening notice. |
| Architecture performance table gives numeric CPU, memory and battery claims and calls the app production-ready (architecture lines 522–545, 631). | Unsupported measurements; no device was available. The architecture notice now labels the values unmeasured. Release signing remains debug-key based ([app Gradle](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/build.gradle.kts:33)). |
| Several historical guides list `BIND_ACCESSIBILITY_SERVICE`, `QUERY_ALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`, `PACKAGE_USAGE_STATS`, and `DISABLE_KEYGUARD` as manifest permissions. | Current merged manifest has no such uses-permission declarations. Binding is on the service element; broad package permissions are removed. UsageStatsUtil exists but is not called by Dart or native blocking paths. |
| Old flow diagrams say accessibility reads preferences on every event and foreground service prevents force-stop. | Current service reads cached values on connection/preference change; force-stop is not prevented. README now explicitly documents force-stop behavior. |
| `SETUP_AND_NEXT_STEPS.md` says minimum API 26 and lists an active plugin accessibility service. | Actual merged manifest has `minSdkVersion=24`; only the custom service is merged. Setup guide now identifies itself as historical. |
| `QUICK_DEVELOPER_REFERENCE.md` lists files and operations from the earlier architecture. | It remains historical; implementation-dependent descriptions should be treated as stale. README points to current code/report. |
| README says no network permission in release. | Merged debug manifest includes INTERNET from Flutter's debug manifest; release source manifests do not declare it. Release merge was not built/inspected in this task, so release absence is inferred from source, not measured from a release APK. |

## Findings

| ID | Severity | Confidence | File:line | What is wrong | Why it matters | Fix | Status |
|---|---|---|---|---|---|---|---|
| F1 | High | Confirmed | [accessibility_service_config.xml:8](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/res/xml/accessibility_service_config.xml:8) | Previous config requested content/window events, content retrieval, interactive windows and key filtering. | Sends unnecessary work through Android accessibility/input paths; plausible source of lag. | Restrict to window-state events, generic feedback, no content retrieval, default flags; native service also sets these explicitly. | Fixed in working tree |
| F2 | High | Confirmed | [FocusBlockerAccessibilityService.kt:117](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/FocusBlockerAccessibilityService.kt:117) | Previous per-event preference reads were costly. | Repeated preference access and set copies can amplify the event firehose. | Refresh cached state from `OnSharedPreferenceChangeListener`; 500 ms same-package debounce; no event-path logging in release. | Fixed in working tree |
| F3 | High | Confirmed | [AppBlockingService.kt:198](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/AppBlockingService.kt:198) | Previous 1-second service loop repeatedly updated notification/state. | Persistent wakeups and SystemUI work while idle. | Single `Handler` boundary callback and system chronometer; cancel callback on stop/destroy. | Fixed in working tree |
| F4 | Medium | Confirmed | [AndroidManifest.xml:5](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/AndroidManifest.xml:5) | Android 14+ requires a service type and type permission for FGS types. | Missing declaration may reject foreground startup. | Declares `specialUse`, `FOREGROUND_SERVICE_SPECIAL_USE`, subtype property; confirm store/platform eligibility before publishing. | Fixed; policy unverified |
| F5 | Medium | Confirmed | [BootCompletedReceiver.kt:37](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/BootCompletedReceiver.kt:37) | Boot receiver starts FGS and handles wall-to-elapsed re-anchor. Device/OEM scheduling and special-use boot allowance were not exercised. | Recovery may vary by OS/OEM; force-stop prevents normal recovery until app is opened. | Keep explicit manual device validation in checklist; don't claim verified reliability. | Proposed validation |
| F6 | Medium | Confirmed | [storage_service.dart:3](/home/benson-cherian-suresh/Development/Disconnect-Application/lib/services/storage_service.dart:3) | UI persists selected apps, schedule and end time separately from native prefs. | Copies can drift after native expiry, force-stop, or partial failure. | Native status is authoritative for active state; future change should make native API own selection/schedule too. | Proposed |
| F7 | Medium | Confirmed | [BlockingActivity.kt:16](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/BlockingActivity.kt:16) | Legacy fullscreen blocking activity is unused and still contains obsolete Back/Home overrides and a window flag. | Misleads maintainers and docs; if reconnected, would have stale behavior. | Leave unlaunched/unexported; remove after deciding whether the home redirect is the desired product behavior. | Proposed |
| F8 | Medium | Confirmed | [MainActivity.kt:130](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/MainActivity.kt:130) | Notification permission request occurs at initialization; result is not used to gate session start. | On Android 13+, user may deny visible notification while the foreground task is still active, reducing transparency. | Add health/status UI for notification permission; retain FGS notification requirement handling. | Proposed |
| F9 | Medium | Confirmed | [app/build.gradle.kts:22](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/build.gradle.kts:22) | Application id is `com.antigravity.focusblocker.focus_blocker` while public/project name is Disconnect and Dart package is `focus_blocker`. | Identity is confusing; changing installed app id is a migration, not a safe cleanup. | Document; rename only with explicit release/migration plan. | Proposed |
| F10 | Medium | Confirmed | [test/widget_test.dart:8](/home/benson-cherian-suresh/Development/Disconnect-Application/test/widget_test.dart:8) | Only two widget startup tests exist. | Doesn't cover session logic or native Android behavior. | Add pure schedule/expiry/exemption tests and device checklist. | Proposed |
| F11 | Low | Confirmed | [UsageStatsUtil.kt:15](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/UsageStatsUtil.kt:15) | Usage stats utility is unused; no `PACKAGE_USAGE_STATS` permission appears in merged manifest. | The class can mislead future usage-stat feature work; no current runtime cost from it. | Remove when implementing usage-based features or add permission flow then. | Proposed |
| F12 | Low | Confirmed | [pubspec.yaml:20](/home/benson-cherian-suresh/Development/Disconnect-Application/pubspec.yaml:20) | `installed_apps` and `shared_preferences_android` trigger Flutter's Kotlin Gradle Plugin migration warning. | Future Flutter versions may fail to build until plugins/app migrate. | Upgrade when compatible versions are available; current build succeeds with warning. | Proposed |
| F13 | Low | Confirmed | [app_selection_screen.dart:64](/home/benson-cherian-suresh/Development/Disconnect-Application/lib/screens/app_selection_screen.dart:64) | App metadata loads through the plugin; first 40 icons are fetched in batches, not via a background isolate. | Large app lists may still create UI/memory work; no profile measurement. | Profile picker on a low-end phone; paginate/lazy icon work if needed. | Proposed |
| F14 | Low | Confirmed | [AppBlockingService.kt:233](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/AppBlockingService.kt:233) | `specialUse` subtype is descriptive but does not by itself establish policy approval or exact use-case eligibility. | Android/Play review may reject an inappropriate FGS type/use. | Verify current Google Play/Android requirements before distribution. | Proposed |

### Manifest and permissions

The built debug merged manifest is `build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml`. It reports min SDK 24 and target SDK 36. Permissions in that manifest: `INTERNET` (from Flutter's debug manifest), `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, and AndroidX's generated signature `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. There is no `BIND_ACCESSIBILITY_SERVICE` uses-permission, `QUERY_ALL_PACKAGES`, `REQUEST_DELETE_PACKAGES`, `SYSTEM_ALERT_WINDOW`, `PACKAGE_USAGE_STATS`, or `DISABLE_KEYGUARD` permission. The service declares `android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"`.

App components in the merged debug manifest:

- Activities: exported launcher `MainActivity`; unexported legacy `BlockingActivity`.
- Services: exported system-bound `FocusBlockerAccessibilityService`; unexported `AppBlockingService` with `foregroundServiceType="specialUse"`.
- Receivers: exported `BootCompletedReceiver`; AndroidX exported `ProfileInstallReceiver` protected by `android.permission.DUMP`.
- Provider: unexported AndroidX `InitializationProvider`.

`POST_NOTIFICATIONS` is requested at runtime on Android 13+ (MainActivity lines 130–138); user denial isn't surfaced in a health check. `startForegroundService()` is used for Android O+ (MainActivity lines 214–219; boot receiver lines 80–86), and service creates its notification channel in `onCreate` before calls to `startForeground`. BIND permission placement and the two app-facing exported flags were corrected. `BootCompletedReceiver` is exported because it receives system broadcasts and accepts only explicit expected actions in code. Direct boot is not supported: receiver listens to `BOOT_COMPLETED`, not `LOCKED_BOOT_COMPLETED`, and preferences are credential-protected.

## Lag investigation

| Hypothesis | Verdict | Evidence / quantification |
|---|---|---|
| H1 Event firehose | **Confirmed as prior configuration risk; current config reduced it.** | Current XML requests only `typeWindowStateChanged`; service also sets only `TYPE_WINDOW_STATE_CHANGED` ([XML:9](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/res/xml/accessibility_service_config.xml:9), [service:144](/home/benson-cherian-suresh/Development/Disconnect-Application/android/app/src/main/kotlin/com/antigravity/focusblocker/focus_blocker/FocusBlockerAccessibilityService.kt:144)). No device event rate available, so percent reduction and mean processing time are **not measured**. |
| H2 Expensive capabilities | **Confirmed removed from current config.** | `canRetrieveWindowContent=false`, `flags=0`; no node/window traversal in event method. No `rootInActiveWindow`, `getSource()` or node traversal on hot path. |
| H3 Key-event filtering | **Confirmed removed.** | No `canRequestFilterKeyEvents`, `FLAG_REQUEST_FILTER_KEY_EVENTS`, or service `onKeyEvent`; current accessibility flags are zero. |
| H4 Work per event | **Confirmed reduced; residual cost remains.** | Cached in-memory set and session fields; package conversion, debounce and membership check. Preferences read in listener and service connect. A debug counter increments on each received event, but logs only every 60 seconds; no duration instrumentation/mean-time measurement. |
| H5 Ticking service | **Confirmed old loop removed.** | One handler callback at boundary; notification built/updated on start or daily boundary, not each second. No persistent timer loop. Flutter active screen still ticks at 1 Hz while visible; it cancels timer on dispose. |
| H6 Activity launch loop | **Ruled out for current implementation.** | Accessibility service doesn't start an activity at all; it calls Home/Lock global action. Thus no `BlockingActivity` relaunch loop. Number of attempts/minute unmeasured. |
| H7 Duplicate service/plugin overhead | **Ruled out in built merged debug manifest.** | Exactly one app AccessibilityService appears; `flutter_accessibility_service` is removed from pubspec and no Dart event-stream subscription exists. Build directory contains stale plugin intermediates from earlier dependency state, but they are not in final merged manifest. |
| H8 Memory pressure | **Cannot verify.** | No device/emulator attached and adb server could not start (`could not install *smartsocket* listener: Operation not permitted`). No `dumpsys meminfo`, CPU or battery stats. Debug APK build size is 168,918,657 bytes; this is not resident memory. |
| H9 OEM behavior | **Cannot verify.** | No OEM device available. Reduced event types, removed key filtering and no service tick address plausible wakeup/CPU triggers but do not establish OEM behavior. |

### Before/after measurements

| Metric | Before | After | Evidence |
|---|---:|---:|---|
| Accessibility events/minute while scrolling | Not measured | Not measured | No Android device/emulator; only debug counter code exists. |
| Mean `onAccessibilityEvent` duration | Not measured | Not measured | No duration instrumentation; do not infer from source. |
| Other-app janky frame percentage/p90/p95/p99 | Not measured | Not measured | No device/emulator or target heavy app. |
| App CPU while idle session active | Not measured | Not measured | No device/emulator. Source has no recurring service tick; accessibility still receives window changes. |
| App wakeups/minute | Not measured | Not measured | No device/emulator/batterystats. |
| Notification `notify()` per second | Prior implementation loop was removed; baseline count not collected | 0/sec by code path; notification updates only at start/state boundary | Source inspection; not device trace. |
| Debug APK | N/A | Built successfully | `build/app/outputs/flutter-apk/app-debug.apk`, 168,918,657 bytes. |

Exact device commands to run once a device is attached (replace `OTHER_APP` with Chrome/YouTube package):

```bash
adb shell dumpsys accessibility
adb shell top -H -d 2 -n 20 | grep -i focusblocker
adb shell dumpsys cpuinfo | grep -i focusblocker
adb shell dumpsys batterystats --charged com.antigravity.focusblocker.focus_blocker
adb shell dumpsys gfxinfo OTHER_APP reset
# Scroll the other app for 60 seconds, then:
adb shell dumpsys gfxinfo OTHER_APP
adb logcat -c
adb logcat -v time | grep -i -E 'FocusBlockerA11y|AppBlockingService|Disconnect'
adb shell dumpsys meminfo com.antigravity.focusblocker.focus_blocker
```

Collect each command for an idle baseline and an active session, then repeat while scrolling the same app/device/OEM for 60 seconds. Do not compare measurements across different devices or refresh rates. `adb devices -l` returned no device; starting the adb daemon failed due sandbox operation restrictions.

## Improvement roadmap

| Priority | Improvement | Impact | Effort | Risk |
|---|---|---|---|---|
| P0 | Device/OEM profiling and manual acceptance runs for current event and session behavior | High | S | Low; measurement only |
| P1 | Native single-source session repository/API; remove duplicate Flutter session fields | High | M | Medium; migration and restart edge cases |
| P1 | Health screen for accessibility, notification, usage access and service-loss state; persistent warning if disabled mid-session | High | M | Medium; permission state differs by OS/OEM |
| P1 | Verify special-use FGS declaration and boot-start restrictions against current Android/Play policy; configure release signing | High | S | Medium; may require different architecture/type |
| P1 | Unit tests for time math, schedule boundaries, exemption and debounce; Android manual/instrumented tests | High | M | Low |
| P2 | Make exemptions user-editable, including essential apps; document unavoidable escape routes | High | M | Medium; whole-device locking safety |
| P2 | Most-used app suggestions with UsageStats access explanation and opt-in | Medium | M | Medium; sensitive special access |
| P2 | Daily per-app budgets, local-only statistics and recurring profiles | High | L | Medium; usage events/data retention |
| P2 | Fallback when service is disabled, force-stop, reboot, process death or expiry; clarify one-time session recovery | High | M | Medium; OS/OEM restrictions |
| P3 | Gentle/strict friction modes and bounded emergency unlocks | Medium | M | Medium; product semantics |
| P3 | Quick Settings tile/widget; opt-in notification muting with separate Notification Listener disclosure | Medium | L | High; new platform permissions/services |
| P3 | A11y/dark-mode/localized strings and replace generated branding; package rename only with migration plan | Medium | M | Medium |
| P3 | Remove unused generated platforms or document Android-only support; add CI analyze/test/build | Low | S | Low |

The working tree also adds a meaningful startup widget test, explicit accessibility disclosure, app picker lazy icon work, cached session status, a debug-only once-per-minute event counter, and CI workflow. These are low-risk improvements already present; no additional feature proposal was implemented during this evidence review.

## Manual test checklist

1. Install debug APK on Android 7/API 24 and a current Android 14/15/16 device; record build/API/OEM.
2. Start a selected-app session with accessibility disabled. Confirm disclosure explains package-name access/local processing, Settings opens, app reports blocking inactive, then enable service and confirm status refreshes on resume.
3. Open one blocked app; confirm it returns Home promptly. Open unblocked apps, Disconnect, Settings, launcher, keyboard, phone and emergency dialer; confirm exemption behavior. Validate banking/maps/messaging apps before using whole-device mode.
4. Run whole-device mode, turn screen off/on and confirm screen lock behavior, safe unlock, and ability to reach Settings/disable the accessibility service.
5. Start a short session, replace it with another session, stop/expire it, and check notification/state cleanup. Change system clock both directions; confirm elapsed timer behavior during current boot. Check expiry when display is off and when app UI is backgrounded.
6. Start a daily schedule crossing midnight; verify before/start/inside/end/next day boundary and equality rejection. Test timezone change and daylight-saving transitions (not currently handled by dedicated receiver).
7. Reboot during an active one-time session and daily schedule. Test app update recovery; separately force-stop app and confirm platform restrictions and honest UI after reopening.
8. Deny notifications on Android 13+, deny/re-enable accessibility mid-session, and observe warning/status. Inspect notification channel importance, sound and chronometer.
9. Scroll a heavy app for 60 seconds with and without an active session. Capture commands above and compare CPU, event counts, frame stats, logs, battery stats and memory.
10. Confirm empty app set, zero/negative duration, invalid schedule, expired session on reboot, and selecting a second session while one is active.

## Build and check evidence

Commands run:

- `flutter --version` → Flutter 3.44.1 stable, Dart 3.12.1.
- `flutter pub get` → Got dependencies; 17 packages have newer versions available but incompatible with current constraints.
- `flutter analyze` → `No issues found! (ran in 1.5s)`.
- `flutter test` → `00:01 +8: All tests passed!` (2 widget tests; test harness emits multiple pump frames).
- `flutter build apk --debug` → `✓ Built build/app/outputs/flutter-apk/app-debug.apk`; Gradle task 21.8s.
- Build warning: Flutter warns app and plugins `installed_apps`, `shared_preferences_android` apply Kotlin Gradle Plugin and may fail in future Flutter versions; migrate to built-in Kotlin when plugins support it.
- `./gradlew :app:processDebugMainManifest` was separately attempted but the wrapper could not write to `/home/benson-cherian-suresh/.gradle/...`; the successful Flutter build generated and was used to inspect the merged manifest.
- `adb devices -l` → no device; adb daemon startup failed with `Operation not permitted`.
- `git diff --check` → no whitespace errors.

## Known limitations

- There are no before/after device performance measurements, no measured event duration, CPU, battery, frame-jank, wakeup or resident-memory figures. The lag source is strongly supported by the old configuration and code pattern, but actual system-wide causal contribution and percentage improvement remain **Likely**, not measured.
- Android 10–16 background activity/FGS behavior and OEM-specific restrictions are not manually tested. The implementation currently avoids background activity launch by sending Home/Lock global actions.
- `BlockingActivity` is dead/legacy code; product behavior is a Home redirect rather than a blocking countdown screen. This is an explicit behavior difference from historical docs.
- Flutter and native prefs remain duplicated for selected apps, end time and schedule. Native active status is used to avoid trusting stale Flutter state, but the data ownership is not fully consolidated.
- Force-stop defeats background services/receivers until the user launches the app again; this cannot be prevented by an ordinary foreground service.
- Direct boot, time-change receiver, notification-permission health UI, low-RAM profiling, Play policy acceptance and release signing were not verified.
- App id is `com.antigravity.focusblocker.focus_blocker`; Kotlin namespace and id are internally aligned, but public naming remains `Disconnect` and Dart package is `focus_blocker`.
- Generated iOS/Linux/macOS/Windows/web folders remain; only Android implements the blocking behavior.
