import 'package:flutter/services.dart';

/// Service for communicating with native Android code via MethodChannel
class NativeService {
  static const platform = MethodChannel('com.antigravity.focusblocker/native');

  /// Initialize the native service
  static Future<void> initialize() async {
    try {
      await platform.invokeMethod('initialize');
    } catch (e) {
      print('Error initializing native service: $e');
    }
  }

  /// Start app blocking with native Android services
  ///
  /// [blockedApps] - List of package names to block
  /// [endTime] - DateTime when blocking should end
  static Future<bool> startBlocking(
    List<String> blockedApps,
    DateTime endTime,
  ) async {
    try {
      final result = await platform.invokeMethod<bool>('startBlocking', {
        'blockedApps': blockedApps,
        'endTimeMillis': endTime.millisecondsSinceEpoch,
      });
      return result ?? false;
    } catch (e) {
      print('Error starting native blocking: $e');
      return false;
    }
  }

  /// Stop app blocking
  static Future<bool> stopBlocking() async {
    try {
      final result = await platform.invokeMethod<bool>('stopBlocking');
      return result ?? false;
    } catch (e) {
      print('Error stopping native blocking: $e');
      return false;
    }
  }

  /// Check if native blocking is currently active
  static Future<bool> isBlockingActive() async {
    try {
      final result = await platform.invokeMethod<bool>('isBlockingActive');
      return result ?? false;
    } catch (e) {
      print('Error checking blocking status: $e');
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
      print('Error getting blocking status: $e');
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
