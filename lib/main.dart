import 'package:flutter/material.dart';
import 'screens/timer_screen.dart';
import 'screens/active_lock_screen.dart';
import 'services/storage_service.dart';
import 'services/native_service.dart';
import 'utils/schedule.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NativeService.initialize();

  final storageService = StorageService();
  final endTime = await storageService.getEndTime();
  final schedule = await storageService.getDailySchedule();
  final blockedApps = await storageService.getBlockedApps();
  final nativeStatus = await NativeService.getBlockingStatus();

  var isLockActive = nativeStatus.isActive;

  if (!isLockActive && endTime != null) {
    if (endTime.isAfter(DateTime.now())) {
      // The Flutter-side session is still pending (for example the process was
      // killed right after the timer was saved). Let ActiveLockScreen start the
      // native session again.
      isLockActive = true;
    } else {
      await storageService.saveEndTime(null);
      await storageService.saveWholeDeviceMode(false);
    }
  }

  if (schedule != null) {
    final window = ScheduleWindow(
      startMinutes: schedule.startMinutes,
      endMinutes: schedule.endMinutes,
    );
    if (!window.isValid) {
      await storageService.clearDailySchedule();
      await NativeService.stopBlocking();
    } else {
      // A saved schedule must keep running even if Android killed the service
      // while the app was closed. Starting it here also re-arms the next
      // boundary after a force-stop.
      if (blockedApps.isNotEmpty) {
        await NativeService.startDailySchedule(
          blockedApps,
          schedule.startMinutes,
          schedule.endMinutes,
        );
      }
      if (window.contains(DateTime.now())) {
        isLockActive = true;
      }
    }
  }

  runApp(FocusBlockerApp(isLockActive: isLockActive));
}

class FocusBlockerApp extends StatelessWidget {
  final bool isLockActive;

  const FocusBlockerApp({super.key, required this.isLockActive});

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
      home: isLockActive ? const ActiveLockScreen() : const TimerScreen(),
    );
  }
}
