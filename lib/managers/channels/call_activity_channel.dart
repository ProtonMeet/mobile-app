import 'dart:io';
import 'package:flutter/services.dart';

class CallActivityChannel {
  static const _ch = MethodChannel('call_activity');

  static bool get supported =>
      Platform.isIOS; // plus runtime iOS version check via native

  static Future<void> start({
    required String callId,
    required String roomName,
    required int participantCount,
    bool isMuted = false,
    bool isVideoEnabled = true,
  }) async {
    if (!supported) {
      return;
    }
    try {
      await _ch.invokeMethod('start', {
        'callId': callId,
        'roomName': roomName,
        'count': participantCount,
        'isMuted': isMuted,
        'isVideoEnabled': isVideoEnabled,
      });
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> update({
    bool? isMuted,
    bool? isVideoEnabled,
    int? participantCount,
    String? roomName,
    int? elapsedSeconds,
  }) async {
    if (!supported) {
      return;
    }
    await _ch.invokeMethod(
      'update',
      {
        'isMuted': isMuted,
        'isVideoEnabled': isVideoEnabled,
        'count': participantCount,
        'roomName': roomName,
        'elapsedSeconds': elapsedSeconds,
      }..removeWhere((k, v) => v == null),
    );
  }

  static Future<void> end({bool immediately = false}) async {
    if (!supported) {
      return;
    }
    await _ch.invokeMethod('end', {'immediately': immediately});
  }

  /// Check if Live Activities are available and enabled
  static Future<Map<String, dynamic>?> checkAvailability() async {
    if (!supported) {
      return {
        'available': false,
        'enabled': false,
        'frequentPushesEnabled': false,
        'iosVersion': 'N/A',
      };
    }
    try {
      final result = await _ch.invokeMethod('checkAvailability');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      return null;
    }
  }
}
