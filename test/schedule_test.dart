import 'package:flutter_test/flutter_test.dart';
import 'package:focus_blocker/utils/schedule.dart';

void main() {
  group('ScheduleWindow', () {
    test('normal window contains times inside it only', () {
      const window = ScheduleWindow(startMinutes: 9 * 60, endMinutes: 17 * 60);
      expect(window.isValid, isTrue);
      expect(window.contains(DateTime(2026, 1, 1, 8, 59)), isFalse);
      expect(window.contains(DateTime(2026, 1, 1, 9, 0)), isTrue);
      expect(window.contains(DateTime(2026, 1, 1, 16, 59)), isTrue);
      expect(window.contains(DateTime(2026, 1, 1, 17, 0)), isFalse);
    });

    test('overnight window crosses midnight', () {
      const window = ScheduleWindow(
        startMinutes: 22 * 60,
        endMinutes: 6 * 60,
      );
      expect(window.contains(DateTime(2026, 1, 1, 23, 0)), isTrue);
      expect(window.contains(DateTime(2026, 1, 2, 5, 59)), isTrue);
      expect(window.contains(DateTime(2026, 1, 2, 6, 0)), isFalse);
      expect(window.contains(DateTime(2026, 1, 2, 12, 0)), isFalse);
    });

    test('next boundary is the end while inside the window', () {
      const window = ScheduleWindow(startMinutes: 9 * 60, endMinutes: 17 * 60);
      final boundary = window.nextBoundary(DateTime(2026, 1, 1, 12, 0));
      expect(boundary, DateTime(2026, 1, 1, 17, 0));
    });

    test('next boundary is the start when outside the window', () {
      const window = ScheduleWindow(startMinutes: 9 * 60, endMinutes: 17 * 60);
      final boundary = window.nextBoundary(DateTime(2026, 1, 1, 20, 0));
      expect(boundary, DateTime(2026, 1, 2, 9, 0));
    });

    test('next boundary of an overnight window is tomorrow morning', () {
      const window = ScheduleWindow(
        startMinutes: 22 * 60,
        endMinutes: 6 * 60,
      );
      final boundary = window.nextBoundary(DateTime(2026, 1, 1, 23, 0));
      expect(boundary, DateTime(2026, 1, 2, 6, 0));
    });

    test('invalid windows are rejected', () {
      expect(
        const ScheduleWindow(startMinutes: 600, endMinutes: 600).isValid,
        isFalse,
      );
      expect(
        const ScheduleWindow(startMinutes: -1, endMinutes: 600).isValid,
        isFalse,
      );
      expect(
        const ScheduleWindow(startMinutes: 600, endMinutes: 1440).isValid,
        isFalse,
      );
    });
  });
}
