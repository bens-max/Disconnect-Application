import 'package:flutter/material.dart';
import '../services/native_service.dart';
import '../services/storage_service.dart';
import 'timer_screen.dart';
import 'app_selection_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  bool _accessibilityEnabled = false;
  bool _notificationsEnabled = true;
  int _selectedAppCount = 0;

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
    final accessibility = await NativeService.isAccessibilityServiceEnabled();
    final notifications = await NativeService.isNotificationEnabled();
    final blockedApps = await StorageService().getBlockedApps();
    if (!mounted) return;
    setState(() {
      _accessibilityEnabled = accessibility;
      _notificationsEnabled = notifications;
      _selectedAppCount = blockedApps.length;
    });
  }

  Future<void> _finish() async {
    await StorageService().setOnboardingComplete(true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TimerScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Disconnect'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Your focus timer needs a little Android access',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Disconnect uses accessibility only to detect when a selected app '
              'opens and return you to the launcher.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 20),
            _setupProgress(theme),
            const SizedBox(height: 16),
            Text(
              'Step 1 of 3',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _permissionCard(
              icon: Icons.accessibility_new,
              title: 'Accessibility access',
              status: _accessibilityEnabled ? 'Enabled' : 'Not enabled',
              enabled: _accessibilityEnabled,
              detail:
                  'Disconnect reads only the foreground app package name. It '
                  'does not read screen text, passwords, messages, app content, '
                  'contacts, or location, and it does not send usage data anywhere.',
              buttonLabel: _accessibilityEnabled
                  ? 'Review accessibility'
                  : 'Enable accessibility',
              onPressed: NativeService.openAccessibilitySettings,
            ),
            const SizedBox(height: 12),
            Text(
              'Step 2 of 3',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _permissionCard(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              status: _notificationsEnabled ? 'Enabled' : 'Denied',
              enabled: _notificationsEnabled,
              detail:
                  'Notifications show the active focus session. Blocking still '
                  'works if notifications are denied.',
              buttonLabel: _notificationsEnabled
                  ? 'Review notifications'
                  : 'Allow notifications',
              onPressed: _notificationsEnabled
                  ? NativeService.openNotificationSettings
                  : NativeService.requestNotificationPermission,
            ),
            const SizedBox(height: 12),
            Text(
              'Step 3 of 3',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _permissionCard(
              icon: Icons.apps,
              title: 'Blocked apps',
              status: _selectedAppCount == 0
                  ? 'Not selected'
                  : '$_selectedAppCount selected',
              enabled: _selectedAppCount > 0,
              detail:
                  'Choose the apps that should pause during your focus session.',
              buttonLabel: 'Select blocked apps',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const AppSelectionScreen(returnSelection: true),
                  ),
                );
                await _refresh();
                return true;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _accessibilityEnabled ? _finish : null,
              child: Text(
                _accessibilityEnabled
                    ? 'Continue'
                    : 'Enable accessibility to continue',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupProgress(ThemeData theme) {
    final completed = <bool>[
      _accessibilityEnabled,
      _notificationsEnabled,
      _selectedAppCount > 0,
    ];
    final titles = const ['Accessibility', 'Notifications', 'Blocked apps'];
    return Row(
      children: [
        for (var i = 0; i < completed.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: completed[i]
                    ? const Color(0xFF03DAC6).withValues(alpha: 0.12)
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: completed[i]
                      ? const Color(0xFF03DAC6).withValues(alpha: 0.5)
                      : Colors.white12,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    completed[i]
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: completed[i] ? const Color(0xFF03DAC6) : Colors.grey,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      titles[i],
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (i != completed.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _permissionCard({
    required IconData icon,
    required String title,
    required String status,
    required bool enabled,
    required String detail,
    required String buttonLabel,
    required Future<bool> Function() onPressed,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? const Color(0xFF03DAC6).withValues(alpha: 0.5)
              : Colors.orange.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  color: enabled ? const Color(0xFF03DAC6) : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            detail,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              await onPressed();
              await Future<void>.delayed(const Duration(milliseconds: 300));
              _refresh();
            },
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
