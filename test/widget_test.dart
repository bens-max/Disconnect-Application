import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import 'package:disconnect/main.dart';
import 'package:disconnect/screens/active_lock_screen.dart';
import 'package:disconnect/screens/timer_screen.dart';
import 'package:disconnect/services/native_service.dart';
import 'package:disconnect/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('com.disconnect/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getBlockingStatus') {
            return {
              'isActive': false,
              'timeLeftMillis': 0,
              'endTimeMillis': 0,
              'blockedApps': <String>[],
              'wholeDevice': false,
              'scheduleEnabled': false,
              'schedules': <Map<String, dynamic>>[],
              'permittedApps': <String>[],
              'nativeServiceActive': false,
              'lastTransitionMillis': 0,
              'exactAlarmsAllowed': true,
              'accessibilityConnected': true,
              'notificationsEnabled': true,
              'supportsWholeDeviceLock': true,
            };
          }
          return true;
        });
  });

  testWidgets('home screen shows the Disconnect timer form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FocusBlockerApp(initialStatus: BlockingStatus.empty()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Make room for focus'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Disconnect'), findsOneWidget);
  });

  testWidgets('zero duration is rejected with a readable message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FocusBlockerApp(initialStatus: BlockingStatus.empty()),
    );
    await tester.pumpAndSettle();

    final disconnectButton = find.widgetWithText(ElevatedButton, 'Disconnect');
    await tester.ensureVisible(disconnectButton);
    tester.widget<ElevatedButton>(disconnectButton).onPressed?.call();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Enter a duration greater than zero.'), findsOneWidget);
  });

  testWidgets(
    'preset durations are available and custom duration fields are preserved',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        FocusBlockerApp(initialStatus: BlockingStatus.empty()),
      );
      await tester.pumpAndSettle();

      expect(find.text('25m'), findsOneWidget);
      expect(find.text('45m'), findsOneWidget);
      expect(find.text('1h'), findsOneWidget);
      expect(find.text('2h'), findsOneWidget);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));
      await tester.enterText(textFields.first, '1');
      await tester.pump();
      expect(
        (tester.widget<TextField>(textFields.first)).controller?.text,
        '1',
      );
    },
  );

  testWidgets('active session disables the timer entry controls', (
    WidgetTester tester,
  ) async {
    const channel = MethodChannel('com.disconnect/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getBlockingStatus') {
            return {
              'isActive': true,
              'timeLeftMillis': 3600000,
              'endTimeMillis': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch,
              'blockedApps': <String>['com.example.app'],
              'nativeServiceActive': true,
              'lastTransitionMillis': DateTime.now().millisecondsSinceEpoch,
            };
          }
          return null;
        });

    await tester.pumpWidget(const MaterialApp(home: TimerScreen()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    final textFields = find.byType(TextField);
    expect(textFields, findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Disconnect'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('selected-app scope requires an explicit edit action', (
    WidgetTester tester,
  ) async {
    const channel = MethodChannel('com.disconnect/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getBlockingStatus') {
            return {
              'isActive': false,
              'timeLeftMillis': 0,
              'endTimeMillis': 0,
              'blockedApps': <String>['com.example.app'],
              'wholeDevice': false,
              'scheduleEnabled': false,
              'schedules': <Map<String, dynamic>>[],
              'permittedApps': <String>[],
              'nativeServiceActive': false,
              'lastTransitionMillis': 0,
              'exactAlarmsAllowed': true,
              'accessibilityConnected': true,
              'notificationsEnabled': true,
              'supportsWholeDeviceLock': true,
            };
          }
          return true;
        });

    await tester.pumpWidget(const MaterialApp(home: TimerScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Selected apps'));
    await tester.pump();

    expect(find.text('Edit selected apps'), findsOneWidget);
    expect(find.text('Choose what to disconnect'), findsNothing);
  });

  testWidgets('schedule countdown does not poll native status each second', (
    WidgetTester tester,
  ) async {
    var statusCalls = 0;
    final boundary = DateTime.now()
        .add(const Duration(minutes: 2))
        .millisecondsSinceEpoch;
    const channel = MethodChannel('com.disconnect/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getBlockingStatus') {
            statusCalls++;
            return {
              'isActive': true,
              'timeLeftMillis': boundary - DateTime.now().millisecondsSinceEpoch,
              'endTimeMillis': boundary,
              'nextBoundaryMillis': boundary,
              'blockedApps': <String>['com.example.app'],
              'wholeDevice': false,
              'scheduleEnabled': true,
              'schedules': [
                {
                  'startMinutes': 0,
                  'endMinutes': 1439,
                  'days': [1, 2, 3, 4, 5, 6, 7],
                },
              ],
              'permittedApps': <String>[],
              'nativeServiceActive': true,
              'lastTransitionMillis': 0,
              'exactAlarmsAllowed': true,
              'accessibilityConnected': true,
              'notificationsEnabled': true,
              'supportsWholeDeviceLock': true,
            };
          }
          return true;
        });

    await tester.pumpWidget(const MaterialApp(home: ActiveLockScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    final initialCalls = statusCalls;
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Daily schedule is blocking selected apps'), findsOneWidget);
    expect(statusCalls, initialCalls);
  });

  test('app picker preferences round trip', () async {
    final storage = StorageService();
    await storage.saveAppPickerPreferences(
      showSystemApps: true,
      category: 'social',
    );

    final preferences = await storage.getAppPickerPreferences();
    expect(preferences.showSystemApps, isTrue);
    expect(preferences.category, 'social');
  });
}
