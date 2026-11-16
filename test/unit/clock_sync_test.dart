import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_buzzer/core/services/clock_sync_service.dart';

void main() {
  group('ClockSyncService Unit Tests', () {
    late ClockSyncService clockSync;

    setUp(() {
      clockSync = ClockSyncService();
    });

    test('Initial state is not synchronized and zero offset', () {
      expect(clockSync.isSynchronized, isFalse);
      expect(clockSync.clockOffsetMs, equals(0));
    });

    test('Explicit offset setting works for deterministic tests', () {
      clockSync.setClockOffsetMs(500);
      expect(clockSync.isSynchronized, isTrue);
      expect(clockSync.clockOffsetMs, equals(500));
    });

    test('Calculates remaining countdown correctly with zero offset', () {
      final now = DateTime.now();
      final deadline = now.add(const Duration(seconds: 10));

      final remaining = clockSync.calculateRemaining(deadline);
      expect(remaining.inSeconds, inInclusiveRange(9, 10));
    });

    test('Calculates remaining countdown under positive server clock skew (+5000ms)', () {
      // Local clock is 5000ms behind server
      clockSync.setClockOffsetMs(5000);

      final now = DateTime.now();
      // Server deadline is 8 seconds from server time (which is now + 5000ms + 8000ms)
      final serverDeadline = now.add(const Duration(milliseconds: 5000 + 8000));

      final remaining = clockSync.calculateRemaining(serverDeadline);
      expect(remaining.inSeconds, inInclusiveRange(7, 8));
    });

    test('Returns Duration.zero when deadline has elapsed', () {
      final pastDeadline = DateTime.now().subtract(const Duration(seconds: 5));
      final remaining = clockSync.calculateRemaining(pastDeadline);
      expect(remaining, equals(Duration.zero));
    });

    test('Returns Duration.zero when deadline is null', () {
      expect(clockSync.calculateRemaining(null), equals(Duration.zero));
    });

    test('syncClock handles server fetch correctly', () async {
      final fakeServerTime = DateTime.now().add(const Duration(milliseconds: 1200));

      await clockSync.syncClock(() async {
        await Future.delayed(const Duration(milliseconds: 20));
        return fakeServerTime;
      });

      expect(clockSync.isSynchronized, isTrue);
      expect(clockSync.clockOffsetMs, isNonZero);
    });
  });
}
