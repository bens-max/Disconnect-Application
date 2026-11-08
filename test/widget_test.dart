import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focus_blocker/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home screen shows the Disconnect timer form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FocusBlockerApp(isLockActive: false));
    await tester.pumpAndSettle();

    expect(find.text('Make room for focus'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Disconnect'), findsOneWidget);
  });

  testWidgets('zero duration is rejected with a readable message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FocusBlockerApp(isLockActive: false));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Disconnect'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a duration greater than zero.'), findsOneWidget);
  });
}
