import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/clock_sync_service.dart';

final countdownProvider =
    StreamProvider.autoDispose.family<Duration, DateTime?>((ref, expiresAt) {
  if (expiresAt == null) {
    return Stream.value(Duration.zero);
  }

  final clockSync = ref.watch(clockSyncServiceProvider);

  return Stream.periodic(const Duration(milliseconds: 100), (_) {
    return clockSync.calculateRemaining(expiresAt);
  }).takeWhile((duration) => duration > Duration.zero);
});
