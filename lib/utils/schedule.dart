/// Pure schedule math shared by the Dart UI and its unit tests.
class ScheduleWindow {
  final int startMinutes;
  final int endMinutes;

  const ScheduleWindow({required this.startMinutes, required this.endMinutes});

  bool get isValid =>
      startMinutes >= 0 &&
      startMinutes < 1440 &&
      endMinutes >= 0 &&
      endMinutes < 1440 &&
      startMinutes != endMinutes;

  /// Handles windows that cross midnight (for example 22:00 -> 06:00).
  bool contains(DateTime time) {
    if (!isValid) return false;
    final current = time.hour * 60 + time.minute;
    if (startMinutes < endMinutes) {
      return current >= startMinutes && current < endMinutes;
    }
    return current >= startMinutes || current < endMinutes;
  }

  /// The end of the current window, or the start of the next one.
  DateTime nextBoundary(DateTime now) {
    final inWindow = contains(now);
    final targetMinutes = inWindow ? endMinutes : startMinutes;
    var target = DateTime(
      now.year,
      now.month,
      now.day,
      targetMinutes ~/ 60,
      targetMinutes % 60,
    );
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }
}
