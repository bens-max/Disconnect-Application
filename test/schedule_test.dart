import 'package:flutter_test/flutter_test.dart';
import 'package:disconnect/utils/schedule.dart';

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
      const window = ScheduleWindow(startMinutes: 22 * 60, endMinutes: 6 * 60);
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
      const window = ScheduleWindow(startMinutes: 22 * 60, endMinutes: 6 * 60);
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

  group('ScheduledWindow overlaps', () {
    test('overnight activity belongs to the selected starting weekday', () {
      const mondayNight = ScheduledWindow(
        startMinutes: 22 * 60,
        endMinutes: 6 * 60,
        days: {DateTime.monday},
      );

      expect(mondayNight.isActiveAt(DateTime(2026, 1, 5, 23)), isTrue);
      expect(mondayNight.isActiveAt(DateTime(2026, 1, 6, 1)), isTrue);
      expect(mondayNight.isActiveAt(DateTime(2026, 1, 6, 6)), isFalse);
      expect(mondayNight.isActiveAt(DateTime(2026, 1, 7, 1)), isFalse);
    });

    test('overnight boundaries end Tuesday morning for a Monday window', () {
      const mondayNight = ScheduledWindow(
        startMinutes: 22 * 60,
        endMinutes: 6 * 60,
        days: {DateTime.monday},
      );

      expect(
        mondayNight.nextBoundary(DateTime(2026, 1, 5, 23)),
        DateTime(2026, 1, 6, 6),
      );
      expect(
        mondayNight.nextBoundary(DateTime(2026, 1, 6, 1)),
        DateTime(2026, 1, 6, 6),
      );
    });

    test('detects overlapping windows on a shared day', () {
      const first = ScheduledWindow(
        startMinutes: 9 * 60,
        endMinutes: 12 * 60,
        days: {1},
      );
      const second = ScheduledWindow(
        startMinutes: 11 * 60,
        endMinutes: 13 * 60,
        days: {1},
      );

      expect(first.overlaps(second), isTrue);
    });

    test('detects overlap across midnight into the following weekday', () {
      const overnight = ScheduledWindow(
        startMinutes: 22 * 60,
        endMinutes: 6 * 60,
        days: {1},
      );
      const morning = ScheduledWindow(
        startMinutes: 5 * 60,
        endMinutes: 7 * 60,
        days: {2},
      );

      expect(overnight.overlaps(morning), isTrue);
    });

    test(
      'does not treat touching boundaries or separate weekdays as overlap',
      () {
        const first = ScheduledWindow(
          startMinutes: 9 * 60,
          endMinutes: 12 * 60,
          days: {1},
        );
        const touching = ScheduledWindow(
          startMinutes: 12 * 60,
          endMinutes: 13 * 60,
          days: {1},
        );
        const otherDay = ScheduledWindow(
          startMinutes: 9 * 60,
          endMinutes: 12 * 60,
          days: {2},
        );

        expect(first.overlaps(touching), isFalse);
        expect(first.overlaps(otherDay), isFalse);
      },
    );
  });
}
