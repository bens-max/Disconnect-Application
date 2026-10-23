import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for communicating with native Android code via MethodChannel
class NativeService {
  static const platform = MethodChannel('com.antigravity.focusblocker/native');

  /// Initialize the native service
  static Future<void> initialize() async {
    try {
      await platform.invokeMethod('initialize');
    } catch (e) {
      debugPrint('Error initializing native service: $e');
    }
  }

  static Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final result = await platform.invokeMethod<bool>(
        'isAccessibilityServiceEnabled',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking accessibility service: $e');
      return false;
    }
  }

  /// Start app blocking with native Android services
  ///
  /// [blockedApps] - List of package names to block
  /// [endTime] - DateTime when blocking should end
  static Future<bool> startBlocking(
    List<String> blockedApps,
    DateTime endTime, {
    bool wholeDevice = false,
  }) async {
    try {
      final result = await platform.invokeMethod<bool>('startBlocking', {
        'blockedApps': blockedApps,
        'endTimeMillis': endTime.millisecondsSinceEpoch,
        'wholeDevice': wholeDevice,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error starting native blocking: $e');
      return false;
    }
  }

  static Future<bool> requestDeviceLock() async {
    try {
      final result = await platform.invokeMethod<bool>('requestDeviceLock');
      return result ?? false;
    } catch (e) {
      debugPrint('Error requesting device lock: $e');
      return false;
    }
  }

  static Future<bool> startDailySchedule(
    List<String> blockedApps,
    int startMinutes,
    int endMinutes,
  ) async {
    try {
      final result = await platform.invokeMethod<bool>('startDailySchedule', {
        'blockedApps': blockedApps,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error starting daily schedule: $e');
      return false;
    }
  }

  /// Stop app blocking
  static Future<bool> stopBlocking() async {
    try {
      final result = await platform.invokeMethod<bool>('stopBlocking');
      return result ?? false;
    } catch (e) {
      debugPrint('Error stopping native blocking: $e');
      return false;
    }
  }

  /// Check if native blocking is currently active
  static Future<bool> isBlockingActive() async {
    try {
      final result = await platform.invokeMethod<bool>('isBlockingActive');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking blocking status: $e');
      return false;
    }
  }

  /// Get current blocking status
  static Future<BlockingStatus> getBlockingStatus() async {
    try {
      final result = await platform.invokeMethod<Map<dynamic, dynamic>>(
        'getBlockingStatus',
      );

      if (result == null) {
        return BlockingStatus.empty();
      }

      return BlockingStatus(
        isActive: result['isActive'] as bool? ?? false,
        timeLeftMillis: result['timeLeftMillis'] as int? ?? 0,
        endTimeMillis: result['endTimeMillis'] as int? ?? 0,
        blockedApps: List<String>.from(
          (result['blockedApps'] as List<dynamic>?) ?? [],
        ),
      );
    } catch (e) {
      debugPrint('Error getting blocking status: $e');
      return BlockingStatus.empty();
    }
  }
}

/// Model class for blocking status information
class BlockingStatus {
  final bool isActive;
  final int timeLeftMillis;
  final int endTimeMillis;
  final List<String> blockedApps;

  BlockingStatus({
    required this.isActive,
    required this.timeLeftMillis,
    required this.endTimeMillis,
    required this.blockedApps,
  });

  factory BlockingStatus.empty() => BlockingStatus(
    isActive: false,
    timeLeftMillis: 0,
    endTimeMillis: 0,
    blockedApps: [],
  );

  Duration get timeLeft => Duration(milliseconds: timeLeftMillis);

  DateTime get endTime => DateTime.fromMillisecondsSinceEpoch(endTimeMillis);

  @override
  String toString() =>
      'BlockingStatus(isActive: $isActive, timeLeft: $timeLeft, '
      'blockedApps: ${blockedApps.length})';
}
