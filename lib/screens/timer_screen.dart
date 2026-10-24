import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/storage_service.dart';
import 'active_lock_screen.dart';
import 'app_selection_screen.dart';
import 'schedule_screen.dart';

enum _TimerType { oneTime, daily }

enum _BlockingScope { allApps, selectedApps }

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  final StorageService _storageService = StorageService();
  final _hoursController = TextEditingController(text: '00');
  final _minutesController = TextEditingController(text: '00');
  _TimerType _timerType = _TimerType.oneTime;
  _BlockingScope _scope = _BlockingScope.selectedApps;
  int _selectedAppCount = 0;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _loadSelectedApps();
  }

  Future<void> _loadSelectedApps() async {
    final apps = await _storageService.getBlockedApps();
    if (mounted) {
      setState(() {
        _selectedAppCount = apps.length;
      });
    }
  }

  Future<void> _chooseApps() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AppSelectionScreen(returnSelection: true),
      ),
    );
    if (changed == true) _loadSelectedApps();
  }

  Future<void> _disconnect() async {
    if (_isStarting) return;
    if (_timerType == _TimerType.daily) {
      if (_scope == _BlockingScope.allApps) {
        _showMessage(
          'Daily whole-device blocking is not available yet. Choose selected apps.',
        );
        return;
      }
      if (_selectedAppCount == 0) {
        _showMessage('Select at least one app for the daily timer.');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScheduleScreen()),
      );
      return;
    }

    final hours = int.tryParse(_hoursController.text) ?? 0;
    final minutes = int.tryParse(_minutesController.text) ?? 0;
    if (hours < 0 || hours > 999 || minutes < 0 || minutes > 59) {
      _showMessage(
        'Hours must be between 0 and 999, and minutes between 0 and 59.',
      );
      return;
    }
    if (hours == 0 && minutes == 0) {
      _showMessage('Enter a duration greater than zero.');
      return;
    }
    if (_scope == _BlockingScope.selectedApps && _selectedAppCount == 0) {
      _showMessage('Select at least one app to disconnect.');
      return;
    }

    setState(() => _isStarting = true);
    await _storageService.clearDailySchedule();
    await _storageService.saveWholeDeviceMode(_scope == _BlockingScope.allApps);
    await _storageService.saveEndTime(
      DateTime.now().add(Duration(hours: hours, minutes: minutes)),
    );
    if (!mounted) return;
    setState(() => _isStarting = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ActiveLockScreen()),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Disconnect', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Choose when and what to disconnect',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWelcomeCard(theme),
              const SizedBox(height: 20),
              _buildTimerTypeSelector(theme),
              const SizedBox(height: 20),
              if (_timerType == _TimerType.oneTime)
                _buildDuration(theme)
              else
                _buildDailyIntro(theme),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isStarting ? null : _disconnect,
                icon: Icon(
                  _timerType == _TimerType.daily
                      ? Icons.schedule
                      : Icons.power_settings_new,
                ),
                label: Text(
                  _isStarting
                      ? 'Starting...'
                      : _timerType == _TimerType.daily
                      ? 'Set daily timer'
                      : 'Disconnect',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _buildScopeSelector(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.22),
            theme.colorScheme.secondary.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.18),
            child: Icon(
              Icons.self_improvement_rounded,
              color: theme.colorScheme.primary,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make room for focus',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 5),
                Text(
                  'Set a timer, then choose the apps you want to pause.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerTypeSelector(ThemeData theme) {
    return SegmentedButton<_TimerType>(
      segments: const [
        ButtonSegment(
          value: _TimerType.oneTime,
          icon: Icon(Icons.timer_outlined),
          label: Text('Time timer'),
        ),
        ButtonSegment(
          value: _TimerType.daily,
          icon: Icon(Icons.event_repeat),
          label: Text('Daily timer'),
        ),
      ],
      selected: {_timerType},
      onSelectionChanged: (value) => setState(() => _timerType = value.first),
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildDuration(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Set your focus duration',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Adjust the hours and minutes below to set your disconnect time.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNumberField(_hoursController, 'Hours'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                ':',
                style: TextStyle(
                  fontSize: 42,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            _buildNumberField(_minutesController, 'Minutes'),
          ],
        ),
      ],
    );
  }

  Widget _buildNumberField(TextEditingController controller, String label) {
    return SizedBox(
      width: 112,
      child: Column(
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(label == 'Minutes' ? 2 : 3),
            ],
            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w300),
            decoration: const InputDecoration(
              hintText: '00',
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyIntro(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.wb_sunny_outlined, color: Color(0xFF03DAC6), size: 30),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Set a repeating From and To window. Selected apps will disconnect automatically every day.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What should be disconnected?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Choose this after setting your timer.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _scopeTile(
          theme,
          _BlockingScope.allApps,
          Icons.phone_android,
          'Select all apps',
          'Lock the whole device during this timer.',
        ),
        const SizedBox(height: 10),
        _scopeTile(
          theme,
          _BlockingScope.selectedApps,
          Icons.apps,
          'Selected apps',
          _selectedAppCount == 0
              ? 'Choose installed apps to disconnect.'
              : '$_selectedAppCount app${_selectedAppCount == 1 ? '' : 's'} selected.',
        ),
      ],
    );
  }

  Widget _scopeTile(
    ThemeData theme,
    _BlockingScope scope,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final selected = _scope == scope;
    return InkWell(
      onTap: () {
        setState(() => _scope = scope);
        if (scope == _BlockingScope.selectedApps) _chooseApps();
      },
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.14)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? theme.colorScheme.primary : Colors.grey,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? theme.colorScheme.primary : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
