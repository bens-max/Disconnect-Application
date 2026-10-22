import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/app_selection_screen.dart';
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
    // Keep the schedule screen available between windows so the user can
    // see the next run and stop the recurring schedule.
    isLockActive = true;
  }

  runApp(FocusBlockerApp(isLockActive: isLockActive));
}

class FocusBlockerApp extends StatelessWidget {
  final bool isLockActive;

  const FocusBlockerApp({super.key, required this.isLockActive});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Blocker',
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
      ),
      home: isLockActive
          ? const ActiveLockScreen()
          : const AppSelectionScreen(),
      routes: {'/selection': (context) => const AppSelectionScreen()},
    );
  }
}
