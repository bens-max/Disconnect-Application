import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/timer_screen.dart';
import 'screens/active_lock_screen.dart';
import 'services/storage_service.dart';
import 'services/native_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize native service
  await NativeService.initialize();

  final storageService = StorageService();
  final endTime = await storageService.getEndTime();
  final schedule = await storageService.getDailySchedule();

  bool isLockActive = false;
  if (endTime != null && DateTime.now().isBefore(endTime)) {
    isLockActive = true;
  }
  if (schedule != null) {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final start = schedule.startMinutes;
    final end = schedule.endMinutes;
    final valid =
        start >= 0 && start < 1440 && end >= 0 && end < 1440 && start != end;
    final inWindow =
        valid &&
        (start < end
            ? currentMinutes >= start && currentMinutes < end
            : currentMinutes >= start || currentMinutes < end);
    isLockActive = isLockActive || inWindow;
    if (!valid) {
      await storageService.clearDailySchedule();
      await NativeService.stopBlocking();
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
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
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
