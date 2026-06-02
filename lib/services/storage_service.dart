import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyBlockedApps = 'blocked_apps';
  static const String _keyEndTime = 'end_time';

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

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
