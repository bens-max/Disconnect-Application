import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/native_service.dart';
import '../utils/schedule.dart';
import 'timer_screen.dart';
import 'blocking_health_screen.dart';

class ActiveLockScreen extends StatefulWidget {
  const ActiveLockScreen({super.key});

  @override
  State<ActiveLockScreen> createState() => _ActiveLockScreenState();
}

class _ActiveLockScreenState extends State<ActiveLockScreen>
    with WidgetsBindingObserver {
  final StorageService _storageService = StorageService();
  final ValueNotifier<Duration> _timeLeft = ValueNotifier(Duration.zero);

  Timer? _timer;
  ScheduleWindow? _schedule;
  List<ScheduledWindow> _schedules = [];
  bool _accessibilityEnabled = false;
  String _statusMessage = 'Initializing...';
  bool _permissionDialogVisible = false;
  BuildContext? _permissionDialogContext;
  bool _nativeBlockingStarted = false;
  bool _showEmergencyExit = false;
  int _blockedAppCount = 0;
  bool _wholeDeviceBlocking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _blockedAppCount = (await _storageService.getBlockedApps()).length;
    _wholeDeviceBlocking = await _storageService.getWholeDeviceMode();
    await _checkPermissions();
    await _startCountdown();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFromNative();
    }
  }

  Future<void> _refreshFromNative() async {
    await _checkPermissions();
    if (_nativeBlockingStarted) {
      await _syncWithNative();
    }
  }

  Future<void> _checkPermissions() async {
    final isEnabled = await NativeService.isAccessibilityServiceEnabled();
    if (!mounted) return;

    setState(() {
      _accessibilityEnabled = isEnabled;
      _statusMessage = isEnabled
          ? 'Accessibility service enabled'
          : 'Accessibility service is off — apps are NOT being blocked';
      _showEmergencyExit = !isEnabled;
    });

    if (isEnabled) {
      _dismissPermissionDialog();
      if (!_nativeBlockingStarted) {
        _nativeBlockingStarted = true;
        try {
          await _startNativeBlocking();
          await _refreshEmergencyExitAvailability();
        } on NativeServiceException catch (error) {
          _nativeBlockingStarted = false;
          _showEmergencyExit = true;
          _setStatus(error.message);
        }
      }
      return;
    }

    _showPermissionDialog();
  }

  void _showPermissionDialog() {
    if (_permissionDialogVisible || !mounted) return;
    _permissionDialogVisible = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _permissionDialogContext = dialogContext;
        return AlertDialog(
          title: const Text('Allow Disconnect to detect app launches?'),
          content: const Text(
            'Android requires an accessibility service so Disconnect can see '
            'which app you open. Disconnect only reads the package name of the '
            'foreground app. It never reads screen text, passwords or messages, '
            'and nothing leaves this device.\n\n'
            'Enable Disconnect under Settings → Accessibility to make blocking '
            'work.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await NativeService.openAccessibilitySettings();
              },
              child: const Text('Open settings'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _endSession();
              },
              child: const Text('End session'),
            ),
          ],
        );
      },
    ).then((_) {
      _permissionDialogVisible = false;
      _permissionDialogContext = null;
    });
  }

  void _dismissPermissionDialog() {
    if (!_permissionDialogVisible) return;
    final dialogContext = _permissionDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
    _permissionDialogVisible = false;
    _permissionDialogContext = null;
  }

  Future<bool> _startNativeBlocking() async {
    final blockedApps = await _storageService.getBlockedApps();
    final wholeDevice = await _storageService.getWholeDeviceMode();
    final schedule = await _storageService.getDailySchedule();
    final schedules = await _storageService.getSchedules();
    final endTime = await _storageService.getEndTime();

    // Native state is authoritative. Avoid restarting an existing session
    // merely because Flutter preferences are stale or missing.
    try {
      final nativeStatus = await NativeService.getBlockingStatus();
      if (nativeStatus.isActive) {
        _setStatus(
          'Blocking active for ${nativeStatus.blockedApps.length} app(s)',
        );
        return true;
      }
    } on NativeServiceException catch (error) {
      _setStatus(error.message);
      return false;
    }

    if (schedules.isNotEmpty) {
      if (blockedApps.isEmpty) return false;
      final success = await NativeService.startSchedules(
        blockedApps,
        schedules.map((item) => item.toJson()).toList(),
      );
      _setStatus(success ? 'Schedules active' : 'Failed to activate schedules');
      return success;
    }

    if (schedule != null) {
      if (blockedApps.isEmpty) {
        _setStatus('Daily schedule has no apps selected');
        _nativeBlockingStarted = false;
        return false;
      }
      final window = ScheduleWindow(
        startMinutes: schedule.startMinutes,
        endMinutes: schedule.endMinutes,
      );
      if (!window.isValid) {
        await _storageService.clearDailySchedule();
        _nativeBlockingStarted = false;
        return false;
      }
      final success = await NativeService.startDailySchedule(
        blockedApps,
        schedule.startMinutes,
        schedule.endMinutes,
      );
      _setStatus(
        success
            ? 'Daily schedule activated for ${blockedApps.length} app(s)'
            : 'Failed to activate daily schedule',
      );
      if (!success) {
        _nativeBlockingStarted = false;
        await _storageService.clearDailySchedule();
        await _storageService.saveEndTime(null);
        await _storageService.saveWholeDeviceMode(false);
      }
      return success;
    }

    if (endTime != null && (blockedApps.isNotEmpty || wholeDevice)) {
      final success = await NativeService.startBlocking(
        blockedApps,
        endTime,
        wholeDevice: wholeDevice,
      );

      if (success) {
        if (wholeDevice) {
          await NativeService.requestDeviceLock();
        }
        _setStatus(
          wholeDevice
              ? 'Whole-device lock activated'
              : 'Native blocking activated for ${blockedApps.length} app(s)',
        );
      } else {
        _nativeBlockingStarted = false;
        await _storageService.saveEndTime(null);
        await _storageService.saveWholeDeviceMode(false);
        _setStatus('Failed to activate native blocking');
      }
      return success;
    }

    _setStatus('No active blocking session');
    return false;
  }

  void _setStatus(String message) {
    if (!mounted) return;
    final failure =
        message.toLowerCase().contains('failed') ||
        message.toLowerCase().contains('could not') ||
        message.toLowerCase().contains('no active');
    if (message == _statusMessage && failure == _showEmergencyExit) return;
    setState(() {
      _statusMessage = message;
      if (failure) {
        _showEmergencyExit = true;
      } else if (_accessibilityEnabled) {
        _showEmergencyExit = false;
      }
    });
  }

  Future<void> _refreshEmergencyExitAvailability() async {
    final endTime = await _storageService.getEndTime();
    final schedules = await _storageService.getSchedules();
    final dailySchedule = await _storageService.getDailySchedule();
    final nativeStatus = await NativeService.getBlockingStatus();
    if (!mounted) return;

    final oneShotLooksPending =
        endTime != null &&
        endTime.isAfter(DateTime.now()) &&
        schedules.isEmpty &&
        dailySchedule == null;
    final nativeSessionMismatch = oneShotLooksPending && !nativeStatus.isActive;

    setState(() {
      _showEmergencyExit = !_accessibilityEnabled || nativeSessionMismatch;
    });
  }

  Future<void> _startCountdown() async {
    final schedules = await _storageService.getSchedules();
    if (schedules.isNotEmpty) {
      _schedules = schedules;
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateSchedulesCountdown(),
      );
      _updateSchedulesCountdown();
      return;
    }
    final schedule = await _storageService.getDailySchedule();
    if (schedule != null) {
      _schedule = ScheduleWindow(
        startMinutes: schedule.startMinutes,
        endMinutes: schedule.endMinutes,
      );
      _updateScheduleCountdown();
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateScheduleCountdown(),
      );
      return;
    }

    final status = await NativeService.getBlockingStatus();
    final DateTime? target;
    if (status.isActive) {
      target = DateTime.now().add(status.timeLeft);
    } else {
      target = await _storageService.getEndTime();
    }
    if (target == null) return;
    _startTicker(target);
  }

  void _startTicker(DateTime target) {
    _timer?.cancel();

    void update() {
      final remaining = target.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;
        _timeLeft.value = Duration.zero;
        _endSession();
        return;
      }
      _timeLeft.value = remaining;
    }

    update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  Future<void> _syncWithNative() async {
    final schedules = await _storageService.getSchedules();
    if (schedules.isNotEmpty) return;
    final schedule = await _storageService.getDailySchedule();
    if (schedule != null) {
      return;
    }

    final status = await NativeService.getBlockingStatus();
    if (!mounted) return;
    if (status.isActive) {
      _startTicker(DateTime.now().add(status.timeLeft));
      return;
    }

    // The native session ended while the app was in the background (expiry,
    // force-stop, service failure). Do not keep claiming it is active.
    _nativeBlockingStarted = false;
    _timer?.cancel();
    _timer = null;
    await _storageService.saveEndTime(null);
    await _storageService.saveWholeDeviceMode(false);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TimerScreen()),
      (_) => false,
    );
  }

  void _updateScheduleCountdown() {
    final schedule = _schedule;
    if (schedule == null) return;
    final now = DateTime.now();
    final target = schedule.nextBoundary(now);
    final inWindow = schedule.contains(now);
    _timeLeft.value = target.difference(now);
    _setStatus(
      inWindow
          ? 'Daily schedule is blocking selected apps'
          : 'Next daily block starts at ${_formatClock(schedule.startMinutes)}',
    );
  }

  void _updateSchedulesCountdown() {
    final now = DateTime.now();
    final inWindow = _schedules.any((schedule) {
      if (!schedule.days.contains(now.weekday)) return false;
      return ScheduleWindow(
        startMinutes: schedule.startMinutes,
        endMinutes: schedule.endMinutes,
      ).contains(now);
    });
    Duration remaining = const Duration(days: 1);
    DateTime? next;
    for (final schedule in _schedules) {
      final window = ScheduleWindow(
        startMinutes: schedule.startMinutes,
        endMinutes: schedule.endMinutes,
      );
      if (!schedule.days.contains(now.weekday) && !window.isValid) continue;
      final boundary = window.nextBoundary(now);
      if (boundary.isAfter(now) && (next == null || boundary.isBefore(next))) {
        next = boundary;
      }
    }
    if (next != null) remaining = next.difference(now);
    _timeLeft.value = remaining;
    _setStatus(
      inWindow ? 'Apps are disconnected' : 'Next scheduled disconnect',
    );
  }

  String _formatClock(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _endSession() async {
    _timer?.cancel();
    _timer = null;
    await _storageService.clearDailySchedule();
    await _storageService.clearSchedules();
    await _storageService.saveEndTime(null);
    await _storageService.saveWholeDeviceMode(false);
    await NativeService.stopBlocking();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TimerScreen()),
      (_) => false,
    );
  }

  Future<void> _confirmEndSchedule() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End the daily schedule?'),
        content: const Text(
          'Selected apps will stop being blocked automatically. You can start '
          'a new schedule from the home screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep blocking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End schedule'),
          ),
        ],
      ),
    );
    if (shouldEnd == true) await _endSession();
  }

  Future<void> _confirmEmergencyExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Emergency exit?'),
        content: const Text(
          'This immediately ends blocking and clears the active native session. '
          'Use this only when the app or timer is stuck.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep blocking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End blocking now'),
          ),
        ],
      ),
    );
    if (shouldExit == true) await _endSession();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timeLeft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to timers',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TimerScreen())),
        ),
        title: const Text('Disconnected'),
        actions: [
          IconButton(
            tooltip: 'Blocking health',
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BlockingHealthScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    const Text(
                      'Time remaining',
                      style: TextStyle(fontSize: 16, color: Color(0xFFB0BEC5)),
                    ),
                    const SizedBox(height: 16),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.96, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: ValueListenableBuilder<Duration>(
                        valueListenable: _timeLeft,
                        builder: (context, timeLeft, _) => Text(
                          _formatDuration(timeLeft),
                          style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF03DAC6),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF232323),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shield_rounded,
                      color: Color(0xFF03DAC6),
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Blocking mode',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _wholeDeviceBlocking
                                ? 'Whole device'
                                : 'Selected apps',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _wholeDeviceBlocking
                          ? 'All apps'
                          : '$_blockedAppCount app${_blockedAppCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Color(0xFF03DAC6),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (_schedule != null) ...[
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: _confirmEndSchedule,
                    child: const Text('End daily schedule'),
                  ),
                ),
              ],
              if (_showEmergencyExit) ...[
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _confirmEmergencyExit,
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('Emergency exit'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
