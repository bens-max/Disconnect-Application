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
    if (_minutes(_from) == _minutes(_to)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('From and To times must be different')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final blockedApps = await _storageService.getBlockedApps();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Schedule'),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(
              'Disconnect selected apps every day',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Choose the daily time span. The schedule repeats automatically, including after a restart.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 48),
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
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeTile(String label, TimeOfDay time, bool isFrom) {
    return InkWell(
      onTap: () => _pickTime(isFrom),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, letterSpacing: 2)),
            Text(
              time.format(context),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w300),
            ),
            const Icon(Icons.edit_outlined),
          ],
        ),
      ),
    );
  }
}
