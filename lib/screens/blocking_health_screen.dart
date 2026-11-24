import 'package:flutter/material.dart';
import '../services/native_service.dart';

class BlockingHealthScreen extends StatefulWidget {
  const BlockingHealthScreen({super.key});

  @override
  State<BlockingHealthScreen> createState() => _BlockingHealthScreenState();
}

class _BlockingHealthScreenState extends State<BlockingHealthScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _accessibility = false;
  bool _notifications = true;
  bool _batteryIgnored = false;
  BlockingStatus _status = BlockingStatus.empty();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final results = await Future.wait<Object>([
      NativeService.isAccessibilityServiceEnabled(),
      NativeService.isNotificationEnabled(),
      NativeService.isBatteryOptimizationIgnored(),
      NativeService.getBlockingStatus(),
    ]);
    if (!mounted) return;
    setState(() {
      _accessibility = results[0] as bool;
      _notifications = results[1] as bool;
      _batteryIgnored = results[2] as bool;
      _status = results[3] as BlockingStatus;
      _loading = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blockingActive =
        _accessibility && _status.nativeServiceActive && _status.isActive;
    final partiallyProtected =
        _accessibility && _status.nativeServiceActive && !_status.isActive;
    final overallTitle = blockingActive
        ? 'Protected'
        : (partiallyProtected ? 'Limited' : 'Not blocking');
    final overallColor = blockingActive
        ? const Color(0xFF03DAC6)
        : (partiallyProtected ? Colors.orange : Colors.grey);
    final overallDetail = blockingActive
        ? 'Your blocking session is active.'
        : (partiallyProtected
              ? 'Blocking is limited; native service is running but no active session is detected.'
              : 'Enable the required settings and start a session.');
    final transition = _status.lastTransitionMillis == 0
        ? 'No transition recorded'
        : _formatTimestamp(
            DateTime.fromMillisecondsSinceEpoch(_status.lastTransitionMillis),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocking health'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: overallColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: overallColor.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          blockingActive
                              ? Icons.shield_rounded
                              : (partiallyProtected
                                    ? Icons.shield_outlined
                                    : Icons.shield_outlined),
                          color: overallColor,
                          size: 38,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                overallTitle,
                                style: TextStyle(
                                  color: overallColor,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                overallDetail,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _healthRow(
                    'Accessibility service',
                    _accessibility ? 'Enabled' : 'Disabled',
                    _accessibility,
                    onAction: NativeService.openAccessibilitySettings,
                    actionLabel: 'Open settings',
                  ),
                  _healthRow(
                    'Native session',
                    _status.nativeServiceActive
                        ? (_status.isActive ? 'Active' : 'Running idle')
                        : 'Inactive',
                    _status.nativeServiceActive,
                  ),
                  _healthRow(
                    'Notifications',
                    _notifications ? 'Enabled' : 'Denied',
                    _notifications,
                    onAction: _notifications
                        ? NativeService.openNotificationSettings
                        : NativeService.requestNotificationPermission,
                    actionLabel: _notifications
                        ? 'Open settings'
                        : 'Allow notifications',
                  ),
                  _healthRow(
                    'Battery optimization',
                    _batteryIgnored
                        ? 'Allowed to run in background'
                        : 'Optimized',
                    _batteryIgnored,
                    onAction: NativeService.openBatteryOptimizationSettings,
                    actionLabel: 'Review settings',
                  ),
                  _healthRow(
                    'Last successful blocking transition',
                    transition,
                    transition != 'No transition recorded',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Blocking does not depend on notifications. If notifications '
                    'are denied, the native session can still keep the timer and '
                    'block selected apps.',
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ],
              ),
            ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}'
        '-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}'
        ':${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _healthRow(
    String title,
    String value,
    bool healthy, {
    Future<bool> Function()? onAction,
    String? actionLabel,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              healthy ? Icons.check_circle : Icons.error_outline,
              color: healthy ? const Color(0xFF03DAC6) : Colors.orange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            if (onAction != null)
              TextButton(
                onPressed: () async {
                  await onAction();
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                  _refresh();
                },
                child: Text(actionLabel ?? 'Open'),
              ),
          ],
        ),
      ),
    );
  }
}
