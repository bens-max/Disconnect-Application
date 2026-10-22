import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyBlockedApps = 'blocked_apps';
  static const String _keyEndTime = 'end_time';
  static const String _keyScheduleStartMinutes = 'schedule_start_minutes';
  static const String _keyScheduleEndMinutes = 'schedule_end_minutes';
  static const String _keyWholeDeviceMode = 'whole_device_mode';

  Future<void> saveBlockedApps(List<String> packageNames) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyBlockedApps, packageNames);
  }

  Future<List<String>> getBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyBlockedApps) ?? [];
  }

  Future<void> saveEndTime(DateTime? endTime) async {
    final prefs = await SharedPreferences.getInstance();
    if (endTime == null) {
      await prefs.remove(_keyEndTime);
    } else {
      await prefs.setString(_keyEndTime, endTime.toIso8601String());
    }
  }

  Future<DateTime?> getEndTime() async {
    final prefs = await SharedPreferences.getInstance();
    final endTimeStr = prefs.getString(_keyEndTime);
    if (endTimeStr == null) return null;
    return DateTime.parse(endTimeStr);
  }

  Future<void> saveDailySchedule({
    required int startMinutes,
    required int endMinutes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyScheduleStartMinutes, startMinutes);
    await prefs.setInt(_keyScheduleEndMinutes, endMinutes);
  }

  Future<({int startMinutes, int endMinutes})?> getDailySchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final start = prefs.getInt(_keyScheduleStartMinutes);
    final end = prefs.getInt(_keyScheduleEndMinutes);
    if (start == null || end == null) return null;
    return (startMinutes: start, endMinutes: end);
  }

  Future<void> clearDailySchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyScheduleStartMinutes);
    await prefs.remove(_keyScheduleEndMinutes);
  }

  Future<void> saveWholeDeviceMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWholeDeviceMode, enabled);
  }

  Future<bool> getWholeDeviceMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyWholeDeviceMode) ?? false;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
