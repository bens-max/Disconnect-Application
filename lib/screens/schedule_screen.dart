import 'package:flutter/material.dart';
import '../services/native_service.dart';
import '../services/storage_service.dart';
import '../utils/schedule.dart';

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
  List<ScheduledWindow> _schedules = [];
  Set<int> _days = {1, 2, 3, 4, 5, 6, 7};

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final schedules = await _storageService.getSchedules();
    if (!mounted) return;
    setState(() => _schedules = schedules);
  }

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
    final window = ScheduleWindow(
      startMinutes: _minutes(_from),
      endMinutes: _minutes(_to),
    );
    if (!window.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('From and To times must be different')),
      );
      return;
    }
    if (_days.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select at least one day')));
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
    final schedules = [
      ..._schedules,
      ScheduledWindow(
        startMinutes: _minutes(_from),
        endMinutes: _minutes(_to),
        days: _days,
      ),
    ];
    await _storageService.saveSchedules(schedules);
    await _storageService.saveDailySchedule(
      startMinutes: _minutes(_from),
      endMinutes: _minutes(_to),
    );
    await _storageService.saveWholeDeviceMode(false);
    await _storageService.saveEndTime(null);

    final success = await NativeService.startSchedules(
      blockedApps,
      schedules.map((schedule) => schedule.toJson()).toList(),
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!success) {
      await _storageService.clearDailySchedule();
      await _storageService.clearSchedules();
      await _storageService.saveWholeDeviceMode(false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the daily schedule')),
      );
      return;
    }
    setState(() {
      _schedules = schedules;
      _isSaving = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Schedule added')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedules'),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_schedules.isNotEmpty) ...[
              const Text(
                'Your schedules',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ..._schedules.map(_buildSavedSchedule),
              const SizedBox(height: 24),
            ],
            const Text(
              'Add schedule',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            _buildTimeTile('FROM', _from, true),
            const SizedBox(height: 16),
            _buildTimeTile('TO', _to, false),
            const SizedBox(height: 18),
            const Text('Days', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (index) {
                final day = index + 1;
                final selected = _days.contains(day);
                const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                return FilterChip(
                  label: Text(names[index]),
                  selected: selected,
                  onSelected: (value) => setState(() {
                    if (value) {
                      _days.add(day);
                    } else {
                      _days.remove(day);
                    }
                  }),
                );
              }),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _startSchedule,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.schedule),
              label: const Text('Add schedule'),
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

  Widget _buildSavedSchedule(ScheduledWindow schedule) {
    final theme = Theme.of(context);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayNames = schedule.days
        .where((day) => day >= 1 && day <= 7)
        .map((day) => names[day - 1])
        .join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatScheduleTime(schedule.startMinutes)} - ${_formatScheduleTime(schedule.endMinutes)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(dayNames, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete schedule',
            onPressed: () => _deleteSchedule(schedule),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  String _formatScheduleTime(int minutes) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return time.format(context);
  }

  Future<void> _deleteSchedule(ScheduledWindow schedule) async {
    final schedules = _schedules
        .where((item) => item.encode() != schedule.encode())
        .toList();
    setState(() => _schedules = schedules);
    await _storageService.saveSchedules(schedules);
    if (schedules.isEmpty) {
      await _storageService.clearDailySchedule();
      await NativeService.stopBlocking();
    } else {
      final blockedApps = await _storageService.getBlockedApps();
      await NativeService.startSchedules(
        blockedApps,
        schedules.map((item) => item.toJson()).toList(),
      );
    }
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
