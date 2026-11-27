import 'package:flutter/material.dart';
import 'screens/timer_screen.dart';
import 'screens/active_lock_screen.dart';
import 'services/storage_service.dart';
import 'services/native_service.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NativeService.initialize();

  final storageService = StorageService();
  final onboardingComplete = await storageService.isOnboardingComplete();
  final nativeStatus = await NativeService.getBlockingStatus();

  var isLockActive = nativeStatus.isActive;
  if (nativeStatus.blockedApps.isNotEmpty) {
    await storageService.saveBlockedApps(nativeStatus.blockedApps);
  } else if (!isLockActive) {
    await storageService.saveEndTime(null);
    await storageService.saveWholeDeviceMode(false);
  }

  runApp(
    FocusBlockerApp(
      isLockActive: isLockActive,
      onboardingComplete: onboardingComplete,
    ),
  );
}

class FocusBlockerApp extends StatelessWidget {
  final bool isLockActive;
  final bool onboardingComplete;

  const FocusBlockerApp({
    super.key,
    required this.isLockActive,
    this.onboardingComplete = true,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Disconnect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFBB86FC),
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFBB86FC),
          secondary: Color(0xFF03DAC6),
          surface: Color(0xFF1E1E1E),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF24242A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            borderSide: BorderSide.none,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E26),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: !onboardingComplete
          ? const OnboardingScreen()
          : isLockActive
          ? const ActiveLockScreen()
          : const TimerScreen(),
    );
  }
}
