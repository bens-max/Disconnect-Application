import 'package:flutter/material.dart';
import '../services/native_service.dart';
import '../services/storage_service.dart';
import 'active_lock_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final StorageService _storageService = StorageService();
  TimeOfDay _from = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 17, minute: 0);
  bool _isSaving = false;

  int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  Future<void> _pickTime(bool isFrom) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: isFrom ? _from : _to,
      helpText: isFrom ? 'Daily schedule starts at' : 'Daily schedule ends at',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = selected;
      } else {
        _to = selected;
      }
    });
  }

  Future<void> _startSchedule() async {
    if (_isSaving) return;
    if (_minutes(_from) == _minutes(_to)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('From and To times must be different')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final blockedApps = await _storageService.getBlockedApps();
    if (blockedApps.isEmpty) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one app first')),
      );
      return;
    }
    await _storageService.saveDailySchedule(
      startMinutes: _minutes(_from),
      endMinutes: _minutes(_to),
    );
    await _storageService.saveWholeDeviceMode(false);
    await _storageService.saveEndTime(null);

    final success = await NativeService.startDailySchedule(
      blockedApps,
      _minutes(_from),
      _minutes(_to),
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the daily schedule')),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ActiveLockScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily schedule'),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.secondary.withValues(alpha: 0.16),
                    theme.colorScheme.surface,
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.25),
                ),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: Color(0x3333DAC6),
                    child: Icon(
                      Icons.wb_sunny_outlined,
                      color: Color(0xFF03DAC6),
                      size: 27,
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'A calmer daily routine',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'The selected apps disconnect automatically every day.',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Choose your focus window',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 14),
            _buildTimeTile('FROM', _from, true),
            const SizedBox(height: 16),
            _buildTimeTile('TO', _to, false),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _startSchedule,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.schedule),
              label: const Text('Start Daily Schedule'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeTile(String label, TimeOfDay time, bool isFrom) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _pickTime(isFrom),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    letterSpacing: 2,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time.format(context),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
            Icon(Icons.edit_outlined, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
