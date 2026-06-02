import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/storage_service.dart';
import 'active_lock_screen.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  final StorageService _storageService = StorageService();
  final TextEditingController _hoursController = TextEditingController(text: '0');
  final TextEditingController _minutesController = TextEditingController(text: '30');

  Future<void> _startBlocking() async {
    final int hours = int.tryParse(_hoursController.text) ?? 0;
    final int minutes = int.tryParse(_minutesController.text) ?? 0;
    
    if (hours == 0 && minutes == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid time')),
      );
      return;
    }

    final duration = Duration(hours: hours, minutes: minutes);
    final endTime = DateTime.now().add(duration);
    
    await _storageService.saveEndTime(endTime);
    
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const ActiveLockScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Focus Time'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(
              'How long do you want to stay focused?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 64),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTimeInput(_hoursController, 'Hours'),
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
                  child: Text(
                    ':',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w200,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                _buildTimeInput(_minutesController, 'Minutes'),
              ],
            ),
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _startBlocking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Disconnect',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ),
            const SizedBox(height: 16),

          ],
        ),
      ),
    );
  }

  Widget _buildTimeInput(TextEditingController controller, String label) {
    return Column(
      children: [
        Container(
          width: 100,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(vertical: 20),
              border: InputBorder.none,
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

