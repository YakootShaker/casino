import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ClockSyncService {
  int _clockOffsetMs = 0;
  bool _isSynchronized = false;

  int get clockOffsetMs => _clockOffsetMs;
  bool get isSynchronized => _isSynchronized;

  /// Explicitly sets the clock offset (useful for unit testing and deterministic simulation)
  void setClockOffsetMs(int offsetMs) {
    _clockOffsetMs = offsetMs;
    _isSynchronized = true;
  }

  /// Synchronizes local clock with server time using RTT calculation:
  /// RTT = T_response - T_request
  /// estimated_server_time_at_response = T_server + (RTT / 2)
  /// offset = estimated_server_time_at_response - T_response
  Future<void> syncClock(Future<DateTime> Function() fetchServerTime) async {
    try {
      final tRequest = DateTime.now().millisecondsSinceEpoch;
      final serverTime = await fetchServerTime();
      final tResponse = DateTime.now().millisecondsSinceEpoch;

      final rtt = max(0, tResponse - tRequest);
      final estimatedServerMsAtResponse = serverTime.millisecondsSinceEpoch + (rtt ~/ 2);
      _clockOffsetMs = estimatedServerMsAtResponse - tResponse;
      _isSynchronized = true;

      debugPrint('Clock synchronized: RTT=${rtt}ms, Offset=${_clockOffsetMs}ms');
    } catch (e) {
      debugPrint('Clock sync warning, using local clock fallback: $e');
    }
  }

  /// Returns the current estimated server time
  DateTime get estimatedServerTime {
    return DateTime.now().add(Duration(milliseconds: _clockOffsetMs));
  }

  /// Calculates remaining countdown duration against server deadline:
  /// remaining = max(0, expiresAt - (local_now + offset))
  Duration calculateRemaining(DateTime? expiresAt) {
    if (expiresAt == null) return Duration.zero;
    final nowServerMs = DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;
    final expiresMs = expiresAt.millisecondsSinceEpoch;
    final remainingMs = max(0, expiresMs - nowServerMs);
    return Duration(milliseconds: remainingMs);
  }
}

final clockSyncServiceProvider = Provider<ClockSyncService>((ref) {
  return ClockSyncService();
});
