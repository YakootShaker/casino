import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/sound_service.dart';
import '../../../../core/services/clock_sync_service.dart';
import '../../data/game_repository.dart';
import '../../data/realtime_service.dart';
import '../../domain/game_state.dart';

class GameStateNotifier extends FamilyAsyncNotifier<GameState, String> {
  StreamSubscription<GameState>? _subscription;
  final ValueNotifier<int?> localActivePlayer = ValueNotifier<int?>(null);

  @override
  FutureOr<GameState> build(String arg) async {
    final roomId = arg;
    final repo = ref.watch(gameRepositoryProvider);
    final realtime = ref.watch(realtimeServiceProvider);
    final clockSync = ref.watch(clockSyncServiceProvider);
    final sound = ref.watch(soundServiceProvider);

    // Initial server clock sync
    clockSync.syncClock(() => repo.getServerTime());

    // Subscribe to real-time events
    realtime.subscribeToRoom(roomId);
    _subscription?.cancel();
    _subscription = realtime.gameStateStream.listen((incomingState) {
      if (incomingState.phase != 'player_answering') {
        localActivePlayer.value = null;
      }
      if (incomingState.phase == 'player_answering') {
        sound.duckAudioOnBuzz();
        sound.playBuzzer();
      }
      state = AsyncData(incomingState);
    });

    ref.onDispose(() {
      _subscription?.cancel();
      localActivePlayer.dispose();
    });

    return repo.getGameState(roomId);
  }

  /// Refreshes state from server
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(gameRepositoryProvider);
      return repo.getGameState(arg);
    });
  }

  /// Starts match from lobby
  Future<void> startGame({String? category}) async {
    final repo = ref.read(gameRepositoryProvider);
    await repo.startGame(arg, category: category);
  }

  /// Referee arms buzzers
  Future<void> armBuzzer() async {
    final repo = ref.read(gameRepositoryProvider);
    localActivePlayer.value = null;
    await repo.armBuzzer(arg);
  }

  /// Player touches buzzer column (hardware touch)
  Future<bool> buzz(int playerIndex) async {
    final currentState = state.valueOrNull;
    if (currentState == null || !currentState.isBuzzerActive) {
      return false;
    }
    if (currentState.isPlayerLocked(playerIndex)) {
      return false;
    }

    // Synchronous local lockout within the UI frame (< 16ms)
    localActivePlayer.value = playerIndex;

    try {
      final repo = ref.read(gameRepositoryProvider);
      final res = await repo.buzz(arg, playerIndex);
      final success = res['success'] == true;
      if (!success) {
        localActivePlayer.value = null;
      }
      return success;
    } catch (e) {
      localActivePlayer.value = null;
      rethrow;
    }
  }

  /// Referee marks answer correct (+1) or incorrect (-1)
  Future<void> judgeMark(bool isCorrect) async {
    final repo = ref.read(gameRepositoryProvider);
    localActivePlayer.value = null;
    await repo.judgeMark(arg, isCorrect);
  }

  /// Turn countdown expired (10s elapsed)
  Future<void> expireTurn() async {
    final repo = ref.read(gameRepositoryProvider);
    await repo.expireTurn(arg);
  }

  /// Manual referee score adjustment
  Future<void> adjustScore(int playerIndex, int delta) async {
    final repo = ref.read(gameRepositoryProvider);
    await repo.adjustScore(arg, playerIndex, delta);
  }

  /// Referee skips question
  Future<void> skipQuestion() async {
    final repo = ref.read(gameRepositoryProvider);
    localActivePlayer.value = null;
    await repo.skipQuestion(arg);
  }
}

final gameStateNotifierProvider =
    AsyncNotifierProvider.family<GameStateNotifier, GameState, String>(() {
  return GameStateNotifier();
});
