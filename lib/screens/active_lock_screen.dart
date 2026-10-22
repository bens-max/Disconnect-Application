import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/constants.dart';
import 'package:flutter_accessibility_service/accessibility_event.dart';
import '../services/storage_service.dart';
import '../services/native_service.dart';

class ActiveLockScreen extends StatefulWidget {
  const ActiveLockScreen({super.key});

  @override
  State<ActiveLockScreen> createState() => _ActiveLockScreenState();
}

class _ActiveLockScreenState extends State<ActiveLockScreen> {
  final StorageService _storageService = StorageService();
  Timer? _timer;
  Duration _timeLeft = Duration.zero;
  StreamSubscription<AccessibilityEvent>? _accessibilitySubscription;
  bool _accessibilityEnabled = false;
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _startCountdown();
    _initAccessibilityListener();
  }

  Future<void> _checkPermissions() async {
    bool isEnabled =
        await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    setState(() {
      _accessibilityEnabled = isEnabled;
      _statusMessage = isEnabled
          ? 'Accessibility Service enabled'
          : 'Accessibility Service not enabled';
    });

    if (!isEnabled) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
            'To block other apps, you must enable the Focus Blocker Accessibility Service in your system settings.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await FlutterAccessibilityService.requestAccessibilityPermission();
                if (!context.mounted) return;
                Navigator.pop(context);
                // Recheck after user returns
                Future.delayed(
                  const Duration(seconds: 1),
                  () => _checkPermissions(),
                );
              },
              child: const Text('Enable'),
            ),
          ],
        ),
      );
    } else {
      // Start native blocking if accessibility is enabled
      _startNativeBlocking();
    }
  }

  Future<void> _startNativeBlocking() async {
    final blockedApps = await _storageService.getBlockedApps();
    final wholeDevice = await _storageService.getWholeDeviceMode();
    final schedule = await _storageService.getDailySchedule();
    final endTime = await _storageService.getEndTime();

    if (schedule != null && blockedApps.isNotEmpty) {
      final success = await NativeService.startDailySchedule(
        blockedApps,
        schedule.startMinutes,
        schedule.endMinutes,
      );
      if (mounted) {
        setState(() {
          _statusMessage = success
              ? 'Daily schedule activated for ${blockedApps.length} app(s)'
              : 'Failed to activate daily schedule';
        });
      }
      return;
    }

    if (endTime != null && (blockedApps.isNotEmpty || wholeDevice)) {
      // Start native Android blocking with custom accessibility service and foreground service
      final success = await NativeService.startBlocking(
        blockedApps,
        endTime,
        wholeDevice: wholeDevice,
      );

      if (success) {
        if (wholeDevice) {
          await NativeService.requestDeviceLock();
          await FlutterAccessibilityService.performGlobalAction(
            GlobalAction.globalActionLockScreen,
          );
        }
        setState(() {
          _statusMessage =
              wholeDevice
                  ? 'Whole-device lock activated'
                  : 'Native blocking activated for ${blockedApps.length} app(s)';
        });
      } else {
        setState(() {
          _statusMessage = 'Failed to activate native blocking';
        });
      }
    }
  }

  void _startCountdown() async {
    final schedule = await _storageService.getDailySchedule();
    if (schedule != null) {
      _updateScheduleCountdown(schedule.startMinutes, schedule.endMinutes);
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateScheduleCountdown(schedule.startMinutes, schedule.endMinutes),
      );
      return;
    }
    final endTime = await _storageService.getEndTime();
    if (endTime == null) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (now.isAfter(endTime)) {
        timer.cancel();
        _onTimeUp();
      } else {
        setState(() {
          _timeLeft = endTime.difference(now);
        });
      }
    });
  }

  void _updateScheduleCountdown(int startMinutes, int endMinutes) {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final start = DateTime(now.year, now.month, now.day, startMinutes ~/ 60, startMinutes % 60);
    var end = DateTime(now.year, now.month, now.day, endMinutes ~/ 60, endMinutes % 60);
    if (endMinutes <= startMinutes) {
      end = end.add(const Duration(days: 1));
    }
    var target = end;
    final inWindow = startMinutes < endMinutes
        ? currentMinutes >= startMinutes && currentMinutes < endMinutes
        : currentMinutes >= startMinutes || currentMinutes < endMinutes;
    if (!inWindow) {
      target = currentMinutes < startMinutes
          ? start
          : start.add(const Duration(days: 1));
    }
    if (mounted) {
      setState(() {
        _timeLeft = target.difference(now);
        _statusMessage = inWindow
            ? 'Daily schedule is blocking selected apps'
            : 'Next daily block starts at ${_formatClock(startMinutes)}';
      });
    }
  }

  String _formatClock(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  void _initAccessibilityListener() async {
    final blockedApps = await _storageService.getBlockedApps();
    final endTime = await _storageService.getEndTime();

    _accessibilitySubscription = FlutterAccessibilityService.accessStream.listen((
      event,
    ) async {
      if (event.packageName == null ||
          !blockedApps.contains(event.packageName)) {
        return;
      }

      // Only react to window state changes (app being opened or coming to foreground)
      if (event.eventType != EventType.typeWindowStateChanged &&
          event.eventType != EventType.typeWindowsChanged) {
        return;
      }

      if (endTime != null && DateTime.now().isBefore(endTime)) {
        // First, try the custom blocking activity via native service
        // If that doesn't work, fall back to home button
        await FlutterAccessibilityService.performGlobalAction(
          GlobalAction.globalActionHome,
        );
      }
    });
  }

  void _onTimeUp() async {
    await _storageService.saveEndTime(null);
    await _storageService.clearDailySchedule();
    await _storageService.saveWholeDeviceMode(false);
    await NativeService.stopBlocking();

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    _timer?.cancel();
    _accessibilitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Focus Blocking Active')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _accessibilityEnabled
                      ? const Color(0xFF03DAC6).withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  border: Border.all(
                    color: _accessibilityEnabled
                        ? const Color(0xFF03DAC6)
                        : Colors.red,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _accessibilityEnabled
                            ? const Color(0xFF03DAC6)
                            : Colors.red,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Timer Display
              Center(
                child: Column(
                  children: [
                    const Text(
                      'Time Remaining',
                      style: TextStyle(fontSize: 16, color: Color(0xFFB0BEC5)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _formatDuration(_timeLeft),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF03DAC6),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Information
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Blocking Mechanism:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFBB86FC),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      '✓',
                      'Custom Accessibility Service monitors app launches',
                    ),
                    _buildInfoRow(
                      '✓',
                      'Foreground Service ensures persistent blocking',
                    ),
                    _buildInfoRow(
                      '✓',
                      'Blocking Activity displays when blocked app is opened',
                    ),
                    _buildInfoRow('✓', 'Automatic home screen redirect'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Warning
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Important:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'The Accessibility Service must remain enabled for the blocking to work effectively. Do not disable it in your device settings.',
                      style: TextStyle(fontSize: 13, color: Colors.orange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Early Stop Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => _showStopConfirmation(),
                  child: const Text('Stop Blocking'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            icon,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF03DAC6),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Color(0xFFB0BEC5)),
            ),
          ),
        ],
      ),
    );
  }

  void _showStopConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Blocking?'),
        content: const Text('Are you sure you want to stop blocking now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _onTimeUp();
            },
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
